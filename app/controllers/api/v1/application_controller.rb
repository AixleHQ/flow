# frozen_string_literal: true

module Api
  module V1
    class ApplicationController < ::ApplicationController
      include Pundit::Authorization
      include AuthorizationConcern
      include PaginationConcern

      self.responder = JsonResponder
      respond_to :json

      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!

      rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

      private

      def policy_context
        BaseContext.new(current_user, params)
      end

      def user_not_authorized
        render json: { error: "Not authorized" }, status: :forbidden
      end

      def record_not_found
        render json: { error: "Record not found" }, status: :not_found
      end
    end
  end
end
