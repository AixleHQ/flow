# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    # Attaching config items at session start.
    #
    # The attachment is what authorizes `get_config_item` to decrypt a value for the
    # session, so the ids cannot be taken on trust from whoever posted them. The rule
    # lives on the model (TerminalSession#config_items_belong_to_project); this test
    # drives it through the endpoint the session form actually posts to.
    class TerminalSessionsConfigItemsTest < ActionDispatch::IntegrationTest
      setup do
        mock_temporal_start
        @company = create(:company)
        @user = create(:user, :employee, :onboarding_completed, company: @company,
                                         password: AuthHelper::TEST_PASSWORD)
        create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
        @project = create(:project, company: @company, owner: @user)
        sign_in_as @user
      end

      def json_headers
        { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      end

      def post_new_session(config_item_ids:, project: @project)
        post api_v1_terminal_sessions_path,
             params: { terminal_session: {
               project_id: project.id, session_type: "agent_session",
               agent_type: "claude_code", mode: "interactive",
               config_item_ids: config_item_ids
             } }.to_json,
             headers: json_headers
      end

      test "attaches the project's config items and reports them back" do
        secret = create(:config_item, :secret, scope: @project, name: "STRIPE_KEY")
        variable = create(:config_item, :variable, scope: @project, name: "API_BASE")

        post_new_session(config_item_ids: [ secret.id, variable.id ])

        assert_response :created
        assert_equal [ secret.id, variable.id ].sort, response.parsed_body["configItemIds"].sort

        session = TerminalSession.find(response.parsed_body["id"])
        assert_equal [ secret.id, variable.id ].sort, session.config_items.pluck(:id).sort
        assert_equal [ secret.id, variable.id ].sort,
                     SessionConfigResolver.new(session).resolve_config_item_ids.sort
      end

      test "refuses a config item from another project" do
        other_project = create(:project, company: @company, owner: @user)
        foreign = create(:config_item, :secret, scope: other_project, name: "OTHER_KEY")

        assert_no_difference -> { TerminalSession.count } do
          post_new_session(config_item_ids: [ foreign.id ])
        end

        assert_response :unprocessable_entity
        assert_match(/must belong to this session's project/, response.parsed_body["errors"].join)
      end

      test "never serializes a config item value" do
        create(:config_item, :secret, scope: @project, name: "STRIPE_KEY", value: "sk_live_abc123")
        item = ConfigItem.find_by(name: "STRIPE_KEY")

        post_new_session(config_item_ids: [ item.id ])

        assert_response :created
        assert_not_includes response.body, "sk_live_abc123"
      end
    end
  end
end
