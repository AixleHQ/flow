# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    # Request-level authorization matrix for Api::V1::TerminalSessionsController.
    #
    # This is a NON-project-scoped JSON API. Its policy
    # (Api::V1::TerminalSessionsPolicy < Api::V1::ApplicationPolicy) gates purely
    # on the read-only (viewer) predicate:
    #
    #   show?    => true          (any authenticated user may read)
    #   create?  => !read_only?   (viewers denied)
    #   destroy? => !read_only?   (viewers denied)
    #   finish?  => !read_only?   (viewers denied)
    #
    # Authorization runs in the `dynamic_authorize!` before_action with
    # context = BaseContext(current_user, params); the policy never loads the
    # actual record, so a viewer mutation is denied (403) *before* any lookup.
    # Record ownership is enforced separately in the controller via
    # `current_user.terminal_sessions.find`, so a session that isn't yours yields
    # 404 (ActiveRecord::RecordNotFound => rescued to :not_found).
    #
    # Terminal sessions are PERSONAL, not project-scoped: neither company-admin
    # rights nor project collaboration grant access to another user's session.
    class TerminalSessionsAuthorizationTest < ActionDispatch::IntegrationTest
      setup do
        @company = create(:company)
        @owner   = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
        @project = create(:project, company: @company, owner: @owner)

        @admin = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD) # NOT owner

        @collaborator = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
        @project.add_collaborator(@collaborator)

        @viewer = create(:user, :viewer, company: @company, email: "client@external.com", password: AuthHelper::TEST_PASSWORD)
        @project.add_collaborator(@viewer)

        @stranger = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)

        @other_company = create(:company)
        @foreign_admin = create(:user, :admin, :onboarding_completed, company: @other_company, password: AuthHelper::TEST_PASSWORD)

        # Every non-owner (regardless of role) is a "stranger" to @owner's session.
        @non_owners = { admin: @admin, collaborator: @collaborator, stranger: @stranger, foreign_admin: @foreign_admin }

        # Sessions are per-user. @owner_session doubles as the cross-user target
        # that every non-owner must be scoped out of (404).
        @owner_session  = create(:terminal_session, user: @owner, state: "ready")
        @viewer_session = create(:terminal_session, user: @viewer, state: "ready")
        @owner_finished = create(:terminal_session, user: @owner, state: "finished") # deletable
        @owner_failed   = create(:terminal_session, user: @owner, state: "failed")   # not finishable
      end

      # ---- show (GET) : show? == true for everyone, then per-user record scope ----

      test "show: owner reads own session" do
        sign_in_as(@owner)
        get api_v1_terminal_session_path(@owner_session), headers: json_headers
        assert_response :success
      end

      test "show: viewer reads own session (reads are permitted for read-only users)" do
        sign_in_as(@viewer)
        get api_v1_terminal_session_path(@viewer_session), headers: json_headers
        assert_response :success
      end

      test "show: non-owners cannot read another user's session (scoped to 404)" do
        # Even a company admin or the project collaborator cannot see the owner's
        # personal session: find is scoped to current_user.terminal_sessions.
        @non_owners.each do |role, actor|
          sign_in_as(actor)
          get api_v1_terminal_session_path(@owner_session), headers: json_headers
          assert_response :not_found, "expected #{role} to be scoped out of another user's session"
        end
      end

      # ---- create (POST) : create? == !read_only? ----

      test "create: viewer is forbidden (read-only)" do
        sign_in_as(@viewer)
        post api_v1_terminal_sessions_path, headers: json_headers
        assert_response :forbidden
      end

      test "create: non-viewers clear authorization (personal, not project-scoped)" do
        # Empty body: a viewer is denied (403) in the before_action; a non-viewer
        # clears authz and only THEN reaches param validation
        # (ActionController::ParameterMissing => 400). A 400 rather than 403 proves
        # the policy permitted them. No valid body is needed to prove "not denied".
        [ @owner, @admin, @collaborator, @stranger, @foreign_admin ].each do |actor|
          sign_in_as(actor)
          post api_v1_terminal_sessions_path, headers: json_headers
          assert_response :bad_request, "expected #{actor.email} to clear authz (400, not 403)"
        end
      end

      # ---- destroy (DELETE) : destroy? == !read_only? ----

      test "destroy: viewer is forbidden (read-only)" do
        # Denial fires in the policy before_action, before the record is loaded:
        # a 403 (not the 404 an ownership miss would give) confirms the read-only
        # gate ran first.
        sign_in_as(@viewer)
        delete api_v1_terminal_session_path(@owner_session), headers: json_headers
        assert_response :forbidden
      end

      test "destroy: owner deletes own finished session" do
        sign_in_as(@owner)
        assert_difference "TerminalSession.count", -1 do
          delete api_v1_terminal_session_path(@owner_finished), headers: json_headers
        end
        assert_response :success
      end

      test "destroy: non-owners cannot delete another user's session (scoped to 404)" do
        @non_owners.each do |role, actor|
          sign_in_as(actor)
          assert_no_difference "TerminalSession.count" do
            delete api_v1_terminal_session_path(@owner_session), headers: json_headers
          end
          assert_response :not_found, "expected #{role} to be scoped out of another user's session"
        end
      end

      # ---- finish (POST member) : finish? == !read_only? ----

      test "finish: viewer is forbidden (read-only)" do
        sign_in_as(@viewer)
        post finish_api_v1_terminal_session_path(@owner_session), headers: json_headers
        assert_response :forbidden
      end

      test "finish: owner clears authorization on own session" do
        # A failed session cannot transition to finishing, so SessionService.finish
        # raises TerminalSession::InvalidStateError and the controller renders 400.
        # A 400 rather than 403 proves the policy permitted the owner (a viewer is
        # 403); no valid finishable state is needed to prove "not denied".
        sign_in_as(@owner)
        post finish_api_v1_terminal_session_path(@owner_failed), headers: json_headers
        assert_response :bad_request
      end

      test "finish: non-owners cannot finish another user's session (scoped to 404)" do
        @non_owners.each do |role, actor|
          sign_in_as(actor)
          post finish_api_v1_terminal_session_path(@owner_session), headers: json_headers
          assert_response :not_found, "expected #{role} to be scoped out of another user's session"
        end
      end

      private

      def json_headers
        { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      end
    end
  end
end
