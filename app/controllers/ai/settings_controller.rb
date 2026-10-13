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
      Ai::Settings.update(params.require(:ai).permit(:provider, :api_key, :remove_api_key, :api_base, :model, :fast_model, :monthly_token_limit))
      Event.record("settings.ai_updated")
      redirect_to settings_ai_path, notice: "Saved"
    end
  end
end
