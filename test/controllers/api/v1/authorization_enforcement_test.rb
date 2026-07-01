# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    # Enforcement-level guarantees for the api/v1 authorization scheme:
    #   - dynamic_authorize! is enabled by default on the whole tree
    #   - a missing policy fails CLOSED (403), not 500 (Pundit::NotDefinedError rescue)
    #   - the deny_read_only_mutation! verb backstop denies a viewer mutation
    #     even if a policy were (hypothetically) mis-classified as permissive
    #   - the Internal namespace is excluded (service auth, no current_user)
    class AuthorizationEnforcementTest < ActionController::TestCase
      tests Api::V1::TerminalSessionsController

      setup do
        @company = create(:company)
        @owner = create(:user, :onboarding_completed, company: @company)
        @project = create(:project, company: @company, owner: @owner)
        @viewer = create(:user, :viewer, company: @company, email: "client@ext.com")
        @project.add_collaborator(@viewer)
      end

      test "missing policy fails closed with 403 (NotDefinedError rescue)" do
        sign_in @owner
        # Force Pundit to behave as if no policy class exists for this action.
        @controller.stubs(:authorize).raises(Pundit::NotDefinedError.new("unable to find policy"))

        get :show, params: { id: create(:terminal_session, user: @owner, project: @project, state: "ready").id }

        assert_response :forbidden
      end

      test "deny_read_only_mutation! backstops a viewer POST even if policy permits" do
        sign_in @viewer
        # Simulate a mis-classified policy that wrongly allows the write.
        Api::V1::TerminalSessionsPolicy.any_instance.stubs(:create?).returns(true)

        post :create, params: {
          terminal_session: { session_type: "agent_session", agent_type: "claude_code", project_id: @project.id }
        }

        assert_response :forbidden
      end
    end

    class VerifyAuthorizedTripwireTest < ActiveSupport::TestCase
      test "verify_authorized after_action is registered in the test environment" do
        callbacks = Api::V1::ApplicationController._process_action_callbacks
        verify = callbacks.find { |cb| cb.filter == :verify_authorized && cb.kind == :after }
        assert verify, "expected after_action :verify_authorized to be active in test env"
      end

      test "Internal base controller does not run dynamic_authorize! before_action" do
        before_filters = Api::V1::Internal::ApplicationController
                           ._process_action_callbacks
                           .select { |cb| cb.kind == :before }
                           .map(&:filter)
        assert_not_includes before_filters, :dynamic_authorize!
        assert_not_includes before_filters, :authenticate_user!
      end
    end
  end
end
