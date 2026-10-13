# frozen_string_literal: true

module Ai
  # Settings › AI (Ai::Settings).
  class SettingsController < ::Settings::BaseController
    include PluginGated
    plugin :ai

    requires_capability "settings:read", only: :show
    requires_capability "settings:write", only: :update

    def show
      @settings = Ai::Settings.current
      @requests = Ai::Request.latest_first.limit(25).to_a
    end

    def update
      before = Ai::Settings.current.provider
      settings = Ai::Settings.update(params.require(:ai).permit(:provider, :api_key, :remove_api_key, :api_base, :model, :fast_model, :monthly_token_limit))
      Event.record("settings.ai_updated")
      load_models(settings) if settings.provider && (settings.provider != before || settings.model_list.empty?)
      redirect_to settings_ai_path, notice: "Saved"
    end

    private

    # A provider just chosen brings its models to pick from (OpenCode lists them without a key).
    def load_models(settings)
      Ai::Settings.remember_models(Ai::Client.new(settings: settings).models)
    rescue Ai::Error => error
      flash[:alert] = "Saved, but #{settings.provider_name}'s models couldn't be listed: #{error.message}"
    end
  end
end
