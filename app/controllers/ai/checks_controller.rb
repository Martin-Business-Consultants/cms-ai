# frozen_string_literal: true

module Ai
  # Asks the model for a tiny answer in a fixed shape: proves the provider, key,
  # model and endpoint all work together.
  class ChecksController < ::Settings::BaseController
    include PluginGated
    plugin :ai

    requires_capability "settings:write", only: :create

    SCHEMA = {type: "object", additionalProperties: false, required: %w[ok], properties: {ok: {type: "boolean"}}}.freeze

    def create
      settings = Ai::Settings.current
      return redirect_to(settings_ai_path, alert: Ai.unavailable_reason) if Ai.unavailable_reason

      Ai::Client.new(settings: settings).structured(purpose: "connection_check", system: "Answer the check.", prompt: "Answer with ok: true.",
        schema: SCHEMA, user: Current.user, max_tokens: 200)
      redirect_to settings_ai_path, notice: "#{settings.model} answered through #{settings.provider_name}"
    rescue Ai::Error => error
      redirect_to settings_ai_path, alert: error.message
    end
  end
end
