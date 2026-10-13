# frozen_string_literal: true

module Ai
  module Api
    # GET /api/ai/requests: the latest 100.
    class RequestsController < BaseController
      requires_capability "settings:read", only: :index

      def index
        render json: {requests: Ai::Request.latest_first.limit(100).map { it.slice(:id, :purpose, :provider, :model, :endpoint, :ok, :http_status, :input_tokens, :output_tokens, :attempts, :duration_ms, :error, :created_at) }}
      end
    end
  end
end
