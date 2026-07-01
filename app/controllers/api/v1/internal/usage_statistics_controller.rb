# frozen_string_literal: true

module Api
  module V1
    module Internal
      class UsageStatisticsController < Api::V1::Internal::ApplicationController
        # POST /api/v1/internal/usage_statistics
        def create
          result = UsageStatisticsService.process(request.raw_post)

          case result.status
          when :ok
            render json: { status: "ok" }
          when :accepted
            head :accepted
          when :bad_request
            render json: { error: result.error }, status: :bad_request
          when :not_found
            render json: { error: result.error }, status: :not_found
          else
            render json: { error: result.error || "Failed to persist usage" }, status: :internal_server_error
          end
        end
      end
    end
  end
end
