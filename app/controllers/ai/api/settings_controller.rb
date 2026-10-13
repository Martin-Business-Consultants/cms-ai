# frozen_string_literal: true

module Ai
  module Api
    # GET|PATCH /api/ai/settings (the key is never read back).
    class SettingsController < BaseController
      requires_capability "settings:read", only: :show
      requires_capability "settings:write", only: :update

      def show
        render json: Ai::Settings.current.to_h
      end

      def update
        settings = Ai::Settings.update(params.require(:settings).permit(:provider, :api_key, :remove_api_key, :api_base, :model, :fast_model, :monthly_token_limit))
        Event.record("settings.ai_updated")
        render json: settings.to_h
      end
    end
  end
end
