# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    # Which company an auth_setup session is created for.
    #
    # An auth_setup session is project-less and it is the session that CREATES an agent
    # credential — and a credential is per company, billed to that company. So the
    # company can never be left unresolved: the credential such a session writes would
    # fail validation, and every read that scopes by company (SessionCompany) would come
    # back empty, which for the cloud paths means "not connected" forever.
    class TerminalSessionsCompanyTest < ActionDispatch::IntegrationTest
      setup do
        mock_temporal_start
        @company = create(:company)
        @other_company = create(:company)
        @user = create(:user, :employee, :onboarding_completed, company: @company,
                                         password: AuthHelper::TEST_PASSWORD)
        create(:company_membership, user: @user, company: @other_company)
        sign_in_as @user
      end

      test "an auth_setup session takes the company the request is acting for" do
        post api_v1_terminal_sessions_path,
             params: { terminal_session: { agent_type: "claude_code", session_type: "auth_setup",
                                           mode: "interactive" } }.to_json,
             headers: json_headers

        assert_response :created
        session = TerminalSession.find(response.parsed_body["id"])
        assert_equal @company.id, session.company_id
      end

      # The API has no company switcher of its own, so a client that knows which company
      # it means says so — and it is validated against the user's active memberships.
      test "an explicit company_id wins over the acting company" do
        post api_v1_terminal_sessions_path,
             params: { company_id: @other_company.id,
                       terminal_session: { agent_type: "claude_code", session_type: "auth_setup",
                                           mode: "interactive" } }.to_json,
             headers: json_headers

        assert_response :created
        assert_equal @other_company.id, TerminalSession.find(response.parsed_body["id"]).company_id
      end

      test "a company the user does not belong to is refused, not silently accepted" do
        stranger_company = create(:company)

        post api_v1_terminal_sessions_path,
             params: { company_id: stranger_company.id,
                       terminal_session: { agent_type: "claude_code", session_type: "auth_setup",
                                           mode: "interactive" } }.to_json,
             headers: json_headers

        assert_response :created
        session = TerminalSession.find(response.parsed_body["id"])
        assert_not_equal stranger_company.id, session.company_id,
                         "a company the user is not a member of must never be bound to a session"
      end

      # Project-bound sessions keep taking the project's company: that is who the work
      # (and the token spend) belongs to, regardless of which company the browser shows.
      test "a project-bound session takes the project's company" do
        project = create(:project, company: @other_company, owner: @user)

        post api_v1_terminal_sessions_path,
             params: { terminal_session: { agent_type: "claude_code", session_type: "agent_session",
                                           mode: "interactive", project_id: project.id } }.to_json,
             headers: json_headers

        assert_response :created
        assert_equal @other_company.id, TerminalSession.find(response.parsed_body["id"]).company_id
      end

      private

      def json_headers
        { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      end
    end
  end
end
