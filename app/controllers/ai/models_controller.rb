# frozen_string_literal: true

module Ai
  # Fetches the provider's models, to pick from.
  class ModelsController < ::Settings::BaseController
    include PluginGated
    plugin :ai

    requires_capability "settings:write", only: :create

    def create
      ids = Ai::Client.new.models
      Ai::Settings.remember_models(ids)
      redirect_to settings_ai_path, notice: "#{ids.size} #{"model".pluralize(ids.size)} to pick from"
    rescue Ai::Error => error
      redirect_to settings_ai_path, alert: error.message
    end
  end
end
