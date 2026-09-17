# frozen_string_literal: true

module Api
  module V1
    module Insights
      # Base for the first-party Aixle Insights pull API.
      #
      # Authenticated by a project-scoped Bearer token (afli_…), not a user
      # session. Sharing must be on; otherwise even a valid token is refused.
      class ApplicationController < Api::V1::ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :dynamic_authorize!, raise: false
        skip_before_action :deny_read_only_mutation!, raise: false
        skip_after_action :verify_authorized, raise: false

        before_action :authenticate_insights_token!
        before_action :require_insights_sharing!

        private

        attr_reader :current_insights_project

        def authenticate_insights_token!
          token = bearer_token
          @current_insights_project = Project.find_by_insights_connection_token(token)
          return head :unauthorized if @current_insights_project.nil?

          @current_insights_project.touch_insights_connection_token_last_used!
        end

        def require_insights_sharing!
          return if current_insights_project.share_usage_with_insights?

          render json: { error: "insights_sharing_disabled", code: "insights_sharing_disabled" },
                 status: :forbidden
        end

        def bearer_token
          header = request.authorization.to_s
          return nil unless header.start_with?("Bearer ")

          header.delete_prefix("Bearer ").strip.presence
        end
      end
    end
  end
end
