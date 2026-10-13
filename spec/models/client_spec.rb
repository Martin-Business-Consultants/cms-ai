# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Client do
  SCHEMA = {type: "object", additionalProperties: false, required: %w[ok], properties: {ok: {type: "boolean"}}}.freeze

  # Answers each call in turn ([status, body] or an exception), recording them.
  class FakeAiTransport
    attr_reader :calls

    def initialize(*answers)
      @answers = answers
      @calls = []
    end

    def call(method, url, headers, body)
      @calls << {method: method, url: url, headers: headers, body: body}
      answer = @answers.shift or raise "no more answers"
      raise answer if answer.is_a?(Exception)

      answer
    end
  end

  let(:waits) { [] }

  def client(*answers, provider: "opencode", model: nil)
    Ai::Settings.update("provider" => provider, "api_key" => "zen-key", "model" => model)
    @transport = FakeAiTransport.new(*answers)
    described_class.new(transport: @transport, wait: ->(seconds) { waits << seconds })
  end

  def ask(client) = client.structured(purpose: "market_plan", system: "Plan it.", prompt: "The facts.", schema: SCHEMA)
  def sent = @transport.calls.last

  it "asks Claude on OpenCode Zen through Anthropic Messages, the schema as a tool it must use" do
    answer = ask(client([200, JSON.generate(content: [{type: "tool_use", name: "market_plan", input: {ok: true}}], usage: {input_tokens: 120, output_tokens: 8})]))

    expect(answer).to eq("ok" => true)
    expect(sent[:url]).to eq("https://opencode.ai/zen/v1/messages")
    expect(sent[:headers]).to include("x-api-key" => "zen-key", "Authorization" => "Bearer zen-key", "anthropic-version" => "2023-06-01")
    expect(sent[:body]).to include(model: "claude-sonnet-5", system: "Plan it.", tool_choice: {type: "tool", name: "market_plan"})
    expect(sent[:body][:tools].first[:input_schema]).to eq(SCHEMA)
    expect(Ai::Request.last).to have_attributes(purpose: "market_plan", provider: "opencode", model: "claude-sonnet-5", endpoint: "messages", ok: true, input_tokens: 120, output_tokens: 8)
  end

  it "asks GPT through OpenAI Responses with a strict schema" do
    answer = ask(client([200, JSON.generate(output: [{type: "message", content: [{type: "output_text", text: %({"ok":true})}]}], usage: {input_tokens: 5, output_tokens: 2})], model: "gpt-5.6"))

    expect(answer).to eq("ok" => true)
    expect(sent[:url]).to eq("https://opencode.ai/zen/v1/responses")
    expect(sent[:body][:text][:format]).to include(type: "json_schema", strict: true, schema: SCHEMA)
  end

  it "asks the open models through chat completions, and falls back to a JSON object for one that won't take a schema" do
    unsupported = [400, JSON.generate(error: {message: "response_format json_schema is not supported for this model"})]
    answer = ask(client(unsupported, [200, JSON.generate(choices: [{message: {content: "```json\n{\"ok\": true}\n```"}, finish_reason: "stop"}], usage: {prompt_tokens: 9, completion_tokens: 3})], model: "kimi-k3"))

    expect(answer).to eq("ok" => true)
    expect(@transport.calls.map { it[:body][:response_format][:type] }).to eq(%w[json_schema json_object])
    expect(sent[:url]).to eq("https://opencode.ai/zen/v1/chat/completions")
    expect(sent[:body][:messages].first[:content]).to include("matching this JSON schema")
    expect(Ai::Request.last).to have_attributes(endpoint: "chat_completions", input_tokens: 9, output_tokens: 3)
  end

  it "asks Gemini through generateContent, for JSON" do
    answer = ask(client([200, JSON.generate(candidates: [{content: {parts: [{text: %({"ok":true})}]}}], usageMetadata: {promptTokenCount: 4, candidatesTokenCount: 1})], model: "gemini-3-pro"))

    expect(answer).to eq("ok" => true)
    expect(sent[:url]).to eq("https://opencode.ai/zen/v1/models/gemini-3-pro:generateContent")
    expect(sent[:headers]).to include("x-goog-api-key" => "zen-key")
  end

  it "reaches each provider where it is" do
    ask(client([200, JSON.generate(content: [{type: "tool_use", input: {ok: true}}])], provider: "anthropic"))
    expect(sent[:url]).to eq("https://api.anthropic.com/v1/messages")
    ask(client([200, JSON.generate(choices: [{message: {content: %({"ok":true})}}])], provider: "openrouter"))
    expect(sent[:url]).to eq("https://openrouter.ai/api/v1/chat/completions")
  end

  it "tries again what may pass, and fails at once on a refused key" do
    expect(ask(client([529, "{}"], Ai::Client::Transient.new("Couldn't reach OpenCode Zen: SocketError"),
      [200, JSON.generate(content: [{type: "tool_use", input: {ok: true}}])]))).to eq("ok" => true)
    expect(waits).to eq([2, 4])
    expect(Ai::Request.last.attempts).to eq(3)

    expect { ask(client([401, JSON.generate(error: {message: "invalid key"})])) }.to raise_error(Ai::Error, "OpenCode Zen didn't accept the key in Settings › AI (invalid key)")
    expect(Ai::Request.last).to have_attributes(ok: false, http_status: 401)
  end

  it "lists the provider's models" do
    expect(client([200, JSON.generate(data: [{id: "kimi-k3"}, {id: "claude-sonnet-5"}])]).models).to eq(%w[claude-sonnet-5 kimi-k3])
    expect(sent[:url]).to eq("https://opencode.ai/zen/v1/models")
  end
end

RSpec.describe Ai do
  before { switch_plugin :ai, on: true }

  it "says why it isn't available, and stops at the month's token limit" do
    expect(described_class.unavailable_reason).to include("choose a provider")
    expect { described_class.structured(purpose: "x", system: "", prompt: "", schema: {}) }.to raise_error(Ai::Unavailable)

    Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key", "monthly_token_limit" => "0.001")
    expect(described_class).to be_available
    Ai::Request.create!(purpose: "x", provider: "opencode", model: "m", input_tokens: 900, output_tokens: 200, created_at: Time.current)
    expect(described_class.unavailable_reason).to include("tokens are used up")

    switch_plugin :ai, on: false
    expect(described_class.unavailable_reason).to include("switch it on")
  end

  it "takes OpenCode's own model names, and keeps the key out of what it reads back" do
    settings = Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key", "model" => "opencode/kimi-k3")

    expect(settings.model).to eq("kimi-k3")
    expect(settings.to_h.to_s).not_to include("zen-key")
    expect(Ai::Settings.update("provider" => "anthropic").model_list).to eq([])
  end
end
