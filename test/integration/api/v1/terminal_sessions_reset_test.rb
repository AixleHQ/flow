# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    # Starting an agent login over. A login that went wrong — a code pasted into the
    # shell, a pane that died — otherwise keeps its container for the 23-hour signal
    # timeout, and onboarding keeps showing it as the agent's session.
    class TerminalSessionsResetTest < ActionDispatch::IntegrationTest
      setup do
        mock_temporal_start
        TemporalService.stubs(:cancel_workflow)
        @company = create(:company)
        @user = create(:user, :employee, :onboarding_completed, company: @company,
                                         password: AuthHelper::TEST_PASSWORD)
        sign_in_as @user
      end

      test "reset cancels a login in progress, so the next connect starts a fresh session" do
        post api_v1_terminal_sessions_path,
             params: { terminal_session: { agent_type: "claude_code", session_type: "auth_setup",
                                           mode: "interactive" } }.to_json,
             headers: json_headers
        stuck = TerminalSession.find(response.parsed_body["id"])

        post reset_api_v1_terminal_session_path(stuck), headers: json_headers

        assert_response :success
        assert_equal "cancelled", response.parsed_body["state"]
        assert_empty @user.terminal_sessions.auth_sessions.active
      end

      test "reset answers with a session that already ended, unchanged" do
        ended = create(:terminal_session, :auth_setup, user: @user, company: @company, state: "failed")

        post reset_api_v1_terminal_session_path(ended), headers: json_headers

        assert_response :success
        assert_equal "failed", ended.reload.state
      end

      test "reset refuses anything but an authentication session" do
        project = create(:project, company: @company, owner: @user)
        work = create(:terminal_session, :agent_session, user: @user, project: project, state: "ready")

        post reset_api_v1_terminal_session_path(work), headers: json_headers

        assert_response :not_found
        assert_equal "ready", work.reload.state
      end

      private

      def json_headers
        { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      end
    end
  end
end
