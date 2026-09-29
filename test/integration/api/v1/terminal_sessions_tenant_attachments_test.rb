# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    # Every id a session is launched with ends up inside the container — a
    # repository cloned with its integration's token, an MCP server with its
    # headers, an asset's bytes. None of them may belong to another tenant.
    class TerminalSessionsTenantAttachmentsTest < ActionDispatch::IntegrationTest
      setup do
        mock_temporal_start
        @company = create(:company)
        @user = create(:user, :employee, :onboarding_completed, company: @company,
                                         password: AuthHelper::TEST_PASSWORD)
        create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
        @project = create(:project, company: @company, owner: @user)

        other_company = create(:company)
        @foreign_project = create(:project, company: other_company, owner: create(:user, company: other_company))
        sign_in_as @user
      end

      def post_new_session(project: @project, **attachments)
        post api_v1_terminal_sessions_path,
             params: { terminal_session: {
               project_id: project.id, session_type: "agent_session",
               agent_type: "claude_code", mode: "interactive", **attachments
             } }.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      end

      def assert_refused(**attachments)
        assert_no_difference -> { TerminalSession.count } do
          post_new_session(**attachments)
        end
        assert_response :unprocessable_entity
        assert_match(/must belong to this project/, response.parsed_body["errors"].join)
      end

      test "refuses another company's repository" do
        foreign = create(:repository, scope: @foreign_project,
                                      integration: create(:integration, company: @foreign_project.company))

        assert_refused(repository_ids: [ foreign.id ])
      end

      test "refuses another company's MCP server" do
        assert_refused(mcp_server_ids: [ create(:mcp_server, :with_headers, scope: @foreign_project).id ])
      end

      test "refuses another company's asset" do
        assert_refused(input_asset_ids: [ create(:asset, scope: @foreign_project.company).id ])
      end

      test "refuses another company's skill" do
        assert_refused(skill_ids: [ create(:skill, scope: @foreign_project).id ])
      end

      test "refuses another company's custom tool" do
        assert_refused(tool_ids: [ create(:tool, scope: @foreign_project).id ])
      end

      test "accepts the project's own resources, the company's assets and platform tools" do
        repo = create(:repository, scope: @project, integration: create(:integration, company: @company))
        server = create(:mcp_server, scope: @project)
        asset = create(:asset, scope: @company)
        platform_tool = create(:tool, :system)

        post_new_session(repository_ids: [ repo.id ], mcp_server_ids: [ server.id ],
                         input_asset_ids: [ asset.id ], tool_ids: [ platform_tool.id ])

        assert_response :created
        session = TerminalSession.find(response.parsed_body["id"])
        assert_equal [ repo.id ], session.repository_ids
        assert_equal [ server.id ], session.mcp_server_ids
        assert_equal [ asset.id ], session.input_asset_ids
        assert_equal [ platform_tool.id ], session.tool_ids
      end

      test "refuses a project of the same company the member cannot open" do
        colleague = create(:user, :employee, company: @company)
        private_project = create(:project, company: @company, owner: colleague)

        assert_no_difference -> { TerminalSession.count } do
          post_new_session(project: private_project)
        end
        assert_response :not_found
      end
    end
  end
end
