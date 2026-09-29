# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    # The API authenticates with the session cookie, so it has to demand the CSRF
    # token the SPA already sends. Forgery protection is off in the test
    # environment by default; these tests switch it on.
    class CsrfProtectionTest < ActionDispatch::IntegrationTest
      setup do
        @previous = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        mock_temporal_start
        @user = create(:user, :employee, :onboarding_completed, :with_company, password: AuthHelper::TEST_PASSWORD)
        @project = create(:project, company: @user.companies.first, owner: @user)
        create(:agent_credential, user: @user, company: @user.companies.first, agent_type: "claude_code")
      end

      teardown { ActionController::Base.allow_forgery_protection = @previous }

      def csrf_token_from(path)
        get path
        response.body[/<meta name="csrf-token" content="([^"]+)"/, 1]
      end

      # The real login form posts its token too, so sign in the way the page does.
      def sign_in_with_token
        post login_path, params: { email: @user.email, password: AuthHelper::TEST_PASSWORD },
                         headers: { "X-CSRF-Token" => csrf_token_from(login_path) }
        follow_redirect! while response.redirect?
      end

      def post_new_session(headers = {})
        post api_v1_terminal_sessions_path,
             params: { terminal_session: { project_id: @project.id, session_type: "agent_session",
                                           agent_type: "claude_code", mode: "interactive" } }.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }.merge(headers)
      end

      test "a cookie-only request without the token is refused" do
        sign_in_with_token

        assert_no_difference -> { TerminalSession.count } do
          post_new_session
        end
        assert_response :unprocessable_entity
      end

      test "the SPA's request with the token goes through" do
        sign_in_with_token
        token = csrf_token_from(company_projects_path)
        assert token.present?

        post_new_session("X-CSRF-Token" => token)

        assert_response :created
      end

      test "machine endpoints under internal need no token" do
        post "/api/v1/internal/usage_statistics", params: "{}", headers: { "CONTENT_TYPE" => "application/json" }

        assert_not_equal 422, response.status
      end
    end
  end
end
