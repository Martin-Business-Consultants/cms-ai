# frozen_string_literal: true

require "net/http"

# Talks to the install's AI provider (Ai::Settings) over Net::HTTP: a plugin
# may use only the gems the core bundles. Each model is asked through the
# endpoint its family is served on (Ai::Settings#protocol_for), for an answer
# in the shape of a JSON schema:
#
#   messages          Anthropic Messages, the schema as a tool the model must use
#   responses         OpenAI Responses, with a strict json_schema format
#   chat_completions  OpenAI-style chat, a strict json_schema format, falling
#                     back to a JSON object for models that don't take one
#   gemini            Google's generateContent, asked for JSON
#
# Every request goes in the ledger (Ai::Request) whatever happens. What may
# pass (the network, 429, 5xx) is tried up to MAX_ATTEMPTS times, waiting
# longer each time; a refused key or a bad request fails at once. The
# transport is injectable: specs answer without the network.
class Ai::Client
  MAX_ATTEMPTS = 3
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 300

  class Transient < Ai::Error; end

  def initialize(settings: Ai::Settings.current, transport: nil, wait: ->(seconds) { sleep(seconds) })
    @settings = settings
    @transport = transport || method(:http)
    @wait = wait
  end

  def structured(purpose:, system:, prompt:, schema:, name: purpose, user: nil, fast: false, max_tokens: 16_000)
    model = @settings.model(fast: fast)
    protocol = @settings.protocol_for(model)
    name = name.to_s.gsub(/[^a-zA-Z0-9_-]/, "_").first(64)
    request = send(:"#{protocol}_request", model: model, system: system, prompt: prompt, schema: schema, name: name, max_tokens: max_tokens)
    call(purpose: purpose, user: user, model: model, protocol: protocol, request: request) do |answer|
      send(:"#{protocol}_answer", answer)
    end
  rescue Unsupported
    raise unless protocol == :chat_completions

    # A model that won't take a schema format: ask for a JSON object, the schema in the instructions.
    request = chat_completions_request(model: model, system: system, prompt: prompt, schema: schema, name: name, max_tokens: max_tokens, strict: false)
    call(purpose: purpose, user: user, model: model, protocol: protocol, request: request) { chat_completions_answer(it) }
  end

  # The provider's models, by id (OpenAI's list format, which OpenCode Zen, OpenRouter and Ollama use too).
  def models
    status, body = @transport.call(:get, "#{@settings.api_base}/models", headers(:list), nil)
    raise Ai::Error, failure(status, parse(body)) unless status.to_i.between?(200, 299)

    Array(parse(body)["data"]).filter_map { it["id"] }.uniq.sort
  rescue Transient => error
    raise Ai::Error, error.message
  end

  private

  class Unsupported < Ai::Error; end

  def call(purpose:, user:, model:, protocol:, request:)
    attempts = 0
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status = answer = error = nil
    begin
      attempts += 1
      status, body = @transport.call(:post, request[:url], headers(protocol), request[:body])
      answer = parse(body)
      raise Transient.new(failure(status, answer)) if status.to_i == 429 || status.to_i >= 500
      raise Unsupported.new(failure(status, answer)) if status.to_i == 400 && protocol == :chat_completions && request.dig(:body, :response_format, :type) == "json_schema" && unsupported_format?(answer)
      raise Ai::Error, failure(status, answer) unless status.to_i.between?(200, 299)

      yield answer
    rescue Transient => problem
      if attempts < MAX_ATTEMPTS
        @wait.call(2**attempts)
        retry
      end
      error = problem
      raise Ai::Error, problem.message
    rescue Ai::Error => problem
      error = problem
      raise
    end
  ensure
    record(purpose: purpose, user: user, model: model, protocol: protocol, url: request&.dig(:url), status: status, answer: answer,
      error: error, attempts: attempts, started: started)
  end

  def headers(protocol)
    key = @settings.api_key.to_s
    base = {"Content-Type" => "application/json", "Accept" => "application/json"}
    base["Authorization"] = "Bearer #{key}" if key.present?
    case protocol
    when :messages then base.merge("x-api-key" => key, "anthropic-version" => "2023-06-01")
    when :gemini then base.merge("x-goog-api-key" => key)
    when :list then (@settings.provider == "anthropic") ? base.merge("x-api-key" => key, "anthropic-version" => "2023-06-01") : base
    else base
    end.compact_blank
  end

  # Anthropic Messages: the schema as a tool the model has to use.
  def messages_request(model:, system:, prompt:, schema:, name:, max_tokens:)
    {url: "#{@settings.api_base}/messages",
     body: {model: model, max_tokens: max_tokens, system: system, messages: [{role: "user", content: prompt}],
            tools: [{name: name, description: "Give the answer in this shape.", input_schema: schema}], tool_choice: {type: "tool", name: name}}}
  end

  def messages_answer(answer)
    raise Ai::Error, "The answer ran too long; try again" if answer["stop_reason"] == "max_tokens"

    use = Array(answer["content"]).find { it["type"] == "tool_use" } or raise Ai::Error, "The model didn't answer in the expected shape; try again"
    use["input"]
  end

  # OpenAI Responses, with a strict schema.
  def responses_request(model:, system:, prompt:, schema:, name:, max_tokens:)
    {url: "#{@settings.api_base}/responses",
     body: {model: model, instructions: system, input: prompt, max_output_tokens: max_tokens,
            text: {format: {type: "json_schema", name: name, schema: schema, strict: true}}}}
  end

  def responses_answer(answer)
    raise Ai::Error, "The answer ran too long; try again" if answer["status"] == "incomplete"

    text = Array(answer["output"]).select { it["type"] == "message" }.flat_map { Array(it["content"]) }.select { it["type"] == "output_text" }.map { it["text"] }.join
    json(text)
  end

  # OpenAI-style chat completions (OpenCode Zen's open models, OpenRouter, Ollama).
  def chat_completions_request(model:, system:, prompt:, schema:, name:, max_tokens:, strict: true)
    format = strict ? {type: "json_schema", json_schema: {name: name, schema: schema, strict: true}} : {type: "json_object"}
    {url: "#{@settings.api_base}/chat/completions",
     body: {model: model, max_tokens: max_tokens, response_format: format,
            messages: [{role: "system", content: with_schema(system, schema)}, {role: "user", content: prompt}]}}
  end

  def chat_completions_answer(answer)
    choice = Array(answer["choices"]).first or raise Ai::Error, "The model sent no answer; try again"
    raise Ai::Error, "The answer ran too long; try again" if choice["finish_reason"] == "length"

    json(choice.dig("message", "content"))
  end

  # Google's generateContent, asked for JSON (its schema format is a subset, so the schema is in the instructions).
  def gemini_request(model:, system:, prompt:, schema:, name:, max_tokens:)
    {url: "#{@settings.api_base}/models/#{model}:generateContent",
     body: {systemInstruction: {parts: [{text: with_schema(system, schema)}]}, contents: [{role: "user", parts: [{text: prompt}]}],
            generationConfig: {responseMimeType: "application/json", maxOutputTokens: max_tokens}}}
  end

  def gemini_answer(answer)
    parts = Array(answer.dig("candidates", 0, "content", "parts"))
    json(parts.map { it["text"] }.join)
  end

  def with_schema(system, schema) = "#{system}\n\nAnswer with one JSON object, and nothing else, matching this JSON schema:\n#{JSON.generate(schema)}"

  # JSON from a model's text, without the code fence some put around it.
  def json(text)
    JSON.parse(text.to_s.strip.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, ""))
  rescue JSON::ParserError
    raise Ai::Error, "The model's answer wasn't the JSON asked for; try again"
  end

  def parse(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end

  def unsupported_format?(answer) = answer.to_json.match?(/response_format|json_schema|structured|not supported/i)

  def failure(status, answer)
    detail = (answer.dig("error", "message") || answer["error"].presence || answer["message"]).then { it.is_a?(String) ? it : nil }
    case status.to_i
    when 401, 403 then "#{@settings.provider_name} didn't accept the key in Settings › AI#{" (#{detail})" if detail}"
    when 404 then "#{@settings.provider_name} doesn't know that model or address#{": #{detail}" if detail}"
    when 429 then "#{@settings.provider_name} is rate limiting this key#{": #{detail}" if detail}"
    else "#{@settings.provider_name} answered #{status}#{": #{detail.to_s.truncate(300)}" if detail}"
    end
  end

  def record(purpose:, user:, model:, protocol:, url:, status:, answer:, error:, attempts:, started:)
    usage = answer.is_a?(Hash) ? (answer["usage"] || answer["usageMetadata"] || {}) : {}
    Ai::Request.create!(purpose: purpose.to_s, user: user, provider: @settings.provider.to_s, model: model.to_s,
      endpoint: protocol.to_s, ok: error.nil? && status.to_i.between?(200, 299), http_status: status,
      input_tokens: (usage["input_tokens"] || usage["prompt_tokens"] || usage["promptTokenCount"]).to_i,
      output_tokens: (usage["output_tokens"] || usage["completion_tokens"] || usage["candidatesTokenCount"]).to_i,
      attempts: attempts, duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
      error: error&.message&.truncate(500), created_at: Time.current)
  rescue => problem
    Rails.logger.error("[ai] couldn't record a request: #{problem.class}: #{problem.message}")
  end

  # [status, body]; the network's own failures may pass.
  def http(method, url, headers, body)
    uri = URI(url)
    request = (method == :get) ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    headers.each { |name, value| request[name] = value }
    request.body = JSON.generate(body) if body
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |connection|
      response = connection.request(request)
      [response.code.to_i, response.body]
    end
  rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError => problem
    raise Transient, "Couldn't reach #{@settings.provider_name}: #{problem.class.name.demodulize}"
  end
end
