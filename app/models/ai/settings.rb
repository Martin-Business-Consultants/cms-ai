# frozen_string_literal: true

# Settings › AI, kept in the core's Setting "ai" (the key among its secrets):
# the provider, its address when it isn't the usual one, the model (and a
# faster one for small jobs), and how many tokens a month plugins may use.
class Ai::Settings
  KEY = "ai"
  # Where each provider is. OpenCode's own (docs: opencode.ai/v2/docs/console/models) is
  # inference/v1; its Go subscription (docs: /v2/docs/console/go) is zen/go/v1.
  PROVIDERS = {
    "opencode" => {name: "OpenCode", hint: "Claude, GPT, Gemini and open models on one key", base: "https://opencode.ai/inference/v1",
                   model: "claude-sonnet-5-5", fast: "claude-haiku-5-5", key: true},
    "opencode_go" => {name: "OpenCode Go", hint: "the open-model subscription", base: "https://opencode.ai/zen/go/v1",
                      model: "kimi-k3", fast: "deepseek-v4-flash", key: true},
    "anthropic" => {name: "Anthropic", hint: "Claude", base: "https://api.anthropic.com/v1", model: "claude-sonnet-5-5", fast: "claude-haiku-5-5", key: true},
    "openai" => {name: "OpenAI", hint: "GPT", base: "https://api.openai.com/v1", model: "gpt-5.6", fast: "gpt-5.4-mini", key: true},
    "openrouter" => {name: "OpenRouter", hint: "any model", base: "https://openrouter.ai/api/v1", model: "anthropic/claude-sonnet-5-5",
                     fast: "anthropic/claude-haiku-5-5", key: true},
    "ollama" => {name: "Ollama", hint: "your own server: nothing leaves it", base: "http://localhost:11434/v1", model: "llama4", fast: "llama4", key: false}
  }.freeze

  def self.current = new(Setting.get(KEY))

  def initialize(data)
    @data = data.to_h.stringify_keys
  end

  def provider = PROVIDERS.key?(@data["provider"]) ? @data["provider"] : nil
  def provider_name = provider && PROVIDERS[provider][:name]
  def api_key = Setting.secret(KEY, "api_key")
  def api_base = (@data["api_base"].presence || (provider && PROVIDERS[provider][:base])).to_s.chomp("/")
  def custom_base? = @data["api_base"].present?

  # The model id as the provider takes it ("opencode/claude-sonnet-5-5", as OpenCode's own config names it, works too).
  def model(fast: false)
    chosen = fast ? @data["fast_model"].presence || @data["model"].presence : @data["model"].presence
    (chosen || (provider && PROVIDERS[provider][fast ? :fast : :model])).to_s.sub(%r{\Aopencode(-go)?/}, "")
  end

  def model_list = Array(@data["models"])
  def models_checked_at = @data["models_checked_at"].presence&.then { Time.zone.parse(it) }

  # Millions of tokens a month, or nil for no limit.
  def monthly_token_limit = @data["monthly_token_limit"].presence&.to_f
  def tokens_this_month = Ai::Request.where(created_at: Time.current.beginning_of_month..).sum("input_tokens + output_tokens")
  def over_limit? = monthly_token_limit.present? && tokens_this_month >= monthly_token_limit * 1_000_000

  def ready? = provider.present? && (api_key.present? || !PROVIDERS[provider][:key]) && usable?(model)

  # The endpoint a model is reached through, nil for one structured answers can't use. OpenCode
  # serves each family on its own, by its documented tables: on OpenCode, Claude and Qwen (but
  # Qwen3.8 Max) as Anthropic Messages, GPT, Grok and Muse as OpenAI Responses, Gemini as Google's
  # generateContent, Jev on an endpoint of its own, and the rest (DeepSeek, GLM, Kimi, MiniMax…) as
  # chat completions; on Go, Claude, MiniMax and Qwen as Messages, GPT, Grok and Muse as Responses.
  def protocol_for(model_id)
    id = model_id.to_s
    case provider
    when "anthropic" then :messages
    when "openai" then :responses
    when "openrouter", "ollama" then :chat_completions
    when "opencode"
      case id
      when /\Ajev/ then nil
      when /\Aqwen3\.8-max/ then :chat_completions
      when /\A(claude|qwen)/ then :messages
      when /\A(gpt|grok|muse|o\d)/ then :responses
      when /\Agemini/ then :gemini
      else :chat_completions
      end
    when "opencode_go"
      case id
      when /\A(claude|minimax|qwen)/ then :messages
      when /\A(gpt|grok|muse)/ then :responses
      else :chat_completions
      end
    end
  end

  def usable?(model_id) = protocol_for(model_id).present?

  FAMILIES = {"claude" => "Claude", "gpt" => "GPT", "o" => "GPT", "gemini" => "Gemini", "grok" => "Grok", "muse" => "Muse", "deepseek" => "DeepSeek",
              "glm" => "GLM", "kimi" => "Kimi", "minimax" => "MiniMax", "qwen" => "Qwen", "mistral" => "Mistral", "mimo" => "MiMo",
              "llama" => "Llama", "nemotron" => "Nemotron", "longcat" => "LongCat", "anthropic" => "Claude", "openai" => "GPT"}.freeze

  # The models to pick from: the provider's list once loaded (those structured answers can use),
  # always with the defaults and what's chosen, grouped by family for the select.
  def model_choices
    ids = (model_list.select { usable?(it) } + [model, model(fast: true), (provider && PROVIDERS[provider][:model]), (provider && PROVIDERS[provider][:fast])].compact_blank).uniq.sort
    groups = ids.group_by { FAMILIES.fetch(it[/\A[a-z]+/i].to_s.downcase, "Other") }
    groups.sort_by { |family, _| [family == "Other" ? 1 : 0, family] }.to_h
  end

  # From Settings › AI's form or the API's PATCH: only what was sent changes.
  # The key changes only when one is typed, and goes with remove_api_key.
  def self.update(params)
    params = params.to_h.stringify_keys
    readers = {
      "provider" => ->(value) { value.to_s.presence_in(PROVIDERS.keys) },
      "api_base" => ->(value) { value.to_s.strip.chomp("/").presence },
      "model" => ->(value) { value.to_s.strip.presence },
      "fast_model" => ->(value) { value.to_s.strip.presence },
      "monthly_token_limit" => ->(value) { value.to_s.strip.presence && [value.to_f, 0].max }
    }
    data = readers.filter_map { |name, read| [name, read.call(params[name])] if params.key?(name) }.to_h
    data["models"] = [] if data.key?("provider") && data["provider"] != current.provider
    Setting.set(KEY, data) if data.any?
    if params["api_key"].present?
      Setting.set_secret(KEY, "api_key" => params["api_key"].to_s.strip)
    elsif ActiveModel::Type::Boolean.new.cast(params["remove_api_key"])
      Setting.set_secret(KEY, "api_key" => "")
    end
    current
  end

  def self.remember_models(ids) = Setting.set(KEY, "models" => ids, "models_checked_at" => Time.current.iso8601)

  def to_h
    {provider: provider, provider_name: provider_name, api_base: api_base, custom_base: custom_base?, model: model, fast_model: model(fast: true),
     key_set: api_key.present?, ready: ready?, models: model_list, monthly_token_limit_millions: monthly_token_limit,
     tokens_this_month: tokens_this_month, over_limit: over_limit?}
  end
end
