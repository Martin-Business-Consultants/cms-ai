# frozen_string_literal: true

require "ai/version"
require "ai/engine"

# AI for the CMS: one provider, set up once in Settings › AI (OpenCode,
# OpenCode Go, Anthropic, OpenAI, OpenRouter, or an Ollama server of your own), that every
# plugin asks through Ai.structured rather than keeping a key of its own.
# Installed from its own repository; off by default.
module Ai
  class Unavailable < StandardError; end

  class Error < StandardError; end

  # Plugin tables are prefixed with the plugin's key.
  def self.table_name_prefix = "ai_"

  # Whether a plugin may ask now: switched on, set up, and within the month's tokens.
  def self.available? = Cms::Plugins.enabled?(:ai) && Ai::Settings.current.ready? && !Ai::Settings.current.over_limit?

  # Why it isn't available, in words for a person; nil when it is.
  def self.unavailable_reason
    settings = Ai::Settings.current
    return "The AI plugin is off: switch it on in Settings › Plugins" unless Cms::Plugins.enabled?(:ai)
    return "AI isn't set up: choose a provider and add its key in Settings › AI" unless settings.ready?

    "This month's AI tokens are used up: raise the limit in Settings › AI" if settings.over_limit?
  end

  # For other plugins: one answer from the install's model in the shape of
  # `schema` (a JSON schema object), as a Hash. `purpose` says who asked
  # ("market_plan"); `system` sets the scene and `prompt` asks. Call it from a
  # job: a model can take a minute or more. Raises Ai::Unavailable when AI is
  # off, unset or over its limit, and Ai::Error when the provider fails.
  def self.structured(purpose:, system:, prompt:, schema:, name: purpose, user: nil, fast: false, max_tokens: 16_000)
    reason = unavailable_reason
    raise Unavailable, reason if reason

    Ai::Client.new.structured(purpose: purpose, name: name, system: system, prompt: prompt, schema: schema, user: user, fast: fast, max_tokens: max_tokens)
  end
end
