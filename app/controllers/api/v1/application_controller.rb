# frozen_string_literal: true

module Api
  module V1
    class ApplicationController < ::ApplicationController
      wrap_parameters false
      include Pundit::Authorization
      include AuthorizationConcern
      include PaginationConcern

      self.responder = JsonResponder
      respond_to :json

      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      # Authorize-by-default: every action in the api/v1 tree is Pundit-checked.
      before_action :dynamic_authorize!
      # Defense-in-depth verb backstop: a read-only client may only issue safe requests.
      before_action :deny_read_only_mutation!

      # Tripwire (test/dev only): fail loudly if an action never called `authorize`.
      # Kept off in production so a coverage gap can't turn into a 500 — the
      # NotDefinedError rescue below already makes prod fail closed (403).
      if Rails.env.test? || Rails.env.development?
        after_action :verify_authorized
      end

      rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
      # Fail closed: a controller shipped without a policy denies (403) instead of 500.
      rescue_from Pundit::NotDefinedError, with: :user_not_authorized
      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

      private

      def policy_context
        BaseContext.new(current_user, params)
      end

      # Defense-in-depth verb backstop, mirroring the policies' read_only?
      # classification and failing CLOSED:
      # - a resolvable company context (project's company / explicit company):
      #   deny unless the user has a non-viewer ACTIVE membership THERE;
      # - no company context: deny users with zero active memberships and pure
      #   viewers. Super admins (no memberships by design) are exempt.
      def deny_read_only_mutation!
        return if request.get? || request.head?
        return unless current_user
        return if current_user.super_admin?

        render json: { error: "Not authorized" }, status: :forbidden if read_only_request?
      end

      def read_only_request?
        if (company = backstop_company)
          membership = current_user.company_memberships.active.find_by(company_id: company.id)
          membership.nil? || membership.viewer?
        else
          current_user.active_memberships.none? || current_user.active_memberships.all?(&:viewer?)
        end
      end

      def backstop_company
        ctx = policy_context
        ctx.respond_to?(:company) ? ctx.company : nil
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
