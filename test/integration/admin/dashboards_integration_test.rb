# frozen_string_literal: true

require "test_helper"

module Admin
  # Smoke coverage for Administrate HTML dashboards (index + show).
  class DashboardsIntegrationTest < ActionDispatch::IntegrationTest
    setup do
      @super_admin = create(
        :user,
        :super_admin,
        :onboarding_completed,
        password: AuthHelper::TEST_PASSWORD,
        password_confirmation: AuthHelper::TEST_PASSWORD
      )
      sign_in_as(@super_admin)

      @company = create(:company)
      @user = create(:user, :onboarding_completed, company: @company)
      @collaborator_user = create(:user, :onboarding_completed, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @board = create(:board, project: @project)
      @column = create(:board_column, board: @board)
      @task = create(:board_task, board: @board, board_column: @column)
      @workflow = create(:workflow, scope: @project)
      @step = create(:step, workflow: @workflow)
      @sub_step = create(:sub_step, step: @step)
      @workflow_run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
      @step_run = create(:step_run, workflow_run: @workflow_run, step: @step)
      @sub_step_run = create(:sub_step_run, step_run: @step_run, sub_step: @sub_step)
      @wra = create(:workflow_run_asset, workflow_run: @workflow_run)
      @tool = create(:tool, scope: @project)
      @tool_file = @tool.tool_files.create!(path: "/workspace/x.rb", content: "1")
      @skill = create(:skill, :with_project_scope, scope: @project)
      @mcp = create(:mcp_server, scope: @project, kind: :custom)
      @oauth_client = OauthClient.create!(
        source: "dcr", issuer: "https://auth.example.com/admin-test", client_id: "admin-test-client",
        authorization_endpoint: "https://auth.example.com/authorize", token_endpoint: "https://auth.example.com/token"
      )
      @oauth_credential = OauthCredential.create!(
        owner: @user, oauth_client: @oauth_client, provider: "mcp:auth.example.com", status: :active
      )
      @integration = create(:integration, company: @company, connected_by: @user)
      @repository = create(:repository, integration: @integration, scope: @project)
      @config_item = create(:config_item, scope: @project)
      @agent = Agent.create!(name: "dashagent", title: "Dash", persona: "p", source: :custom, scope: @project)
      @credential = create(:agent_credential, user: @user)
      @terminal_session = create(:terminal_session, user: @user, project: @project)
      @session_log = create(:session_log, terminal_session: @terminal_session)
      @asset = create(:asset, :with_company_scope, scope: @company, created_by: @user)
      @asset_version = create(:asset_version, asset: @asset, uploaded_by: @user)
      @tool_result = create(:tool_result, terminal_session: @terminal_session)
      @collaborator = create(:project_collaborator, project: @project, user: @collaborator_user)
      @task_comment = create(:task_comment, board_task: @task, author: @user)
      @task_asset = create(:task_asset, board_task: @task, author: @user)
      @activity = BoardActivity.create!(board: @board, board_task: @task, actor: @user, event_type: :task_created, actor_type: :human)
      @preset = BoardViewPreset.create!(board: @board, user: @user, name: "Mine", filters: { "columns" => [] }, shared: false)
      @transition = ColumnTransition.create!(board_task: @task, from_column: nil, to_column: @column, actor: @user, actor_type: :human)
      @binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow, trigger_mode: :manual, cooldown_seconds: 0)
      @usage = UsageStatistic.create!(
        terminal_session: @terminal_session,
        tokens: 0,
        cost_cents: 0,
        input_tokens: 0,
        output_tokens: 0,
        cache_write_tokens: 0,
        cache_read_tokens: 0
      )
      @quota = NamespaceResourceQuota.create!(scope: @project, max_pods: 10)
    end

    test "users#index" do
      get admin_users_path
      assert_response :success
    end

    test "users#show" do
      get admin_user_path(@user)
      assert_response :success
    end

    test "companies#index" do
      get admin_companies_path
      assert_response :success
    end

    test "companies#show" do
      get admin_company_path(@company)
      assert_response :success
    end

    test "projects#index" do
      get admin_projects_path
      assert_response :success
    end

    test "projects#show" do
      get admin_project_path(@project)
      assert_response :success
    end

    test "project_collaborators#index" do
      get admin_project_collaborators_path
      assert_response :success
    end

    test "project_collaborators#show" do
      get admin_project_collaborator_path(@collaborator)
      assert_response :success
    end

    test "agent_credentials#index" do
      get admin_agent_credentials_path
      assert_response :success
    end

    test "agent_credentials#show" do
      get admin_agent_credential_path(@credential)
      assert_response :success
    end

    test "oauth_clients#index" do
      get admin_oauth_clients_path
      assert_response :success
    end

    test "oauth_clients#show" do
      get admin_oauth_client_path(@oauth_client)
      assert_response :success
    end

    test "oauth_credentials#index" do
      get admin_oauth_credentials_path
      assert_response :success
    end

    test "oauth_credentials#show" do
      get admin_oauth_credential_path(@oauth_credential)
      assert_response :success
    end

    test "terminal_sessions#index" do
      get admin_terminal_sessions_path
      assert_response :success
    end

    test "terminal_sessions#show" do
      get admin_terminal_session_path(@terminal_session)
      assert_response :success
    end

    test "session_logs#index" do
      get admin_session_logs_path
      assert_response :success
    end

    test "session_logs#show" do
      get admin_session_log_path(@session_log)
      assert_response :success
    end

    test "assets#index" do
      get admin_assets_path
      assert_response :success
    end

    test "assets#show" do
      get admin_asset_path(@asset)
      assert_response :success
    end

    test "asset_versions#index" do
      get admin_asset_versions_path
      assert_response :success
    end

    test "asset_versions#show" do
      get admin_asset_version_path(@asset_version)
      assert_response :success
    end

    test "tool_results#index" do
      get admin_tool_results_path
      assert_response :success
    end

    test "tool_results#show" do
      get admin_tool_result_path(@tool_result)
      assert_response :success
    end

    test "agents#index" do
      get admin_agents_path
      assert_response :success
    end

    test "agents#show" do
      get admin_agent_path(@agent)
      assert_response :success
    end

    test "boards#index" do
      get admin_boards_path
      assert_response :success
    end

    test "boards#show" do
      get admin_board_path(@board)
      assert_response :success
    end

    test "board_activities#index" do
      get admin_board_activities_path
      assert_response :success
    end

    test "board_activities#show" do
      get admin_board_activity_path(@activity)
      assert_response :success
    end

    test "board_columns#index" do
      get admin_board_columns_path
      assert_response :success
    end

    test "board_columns#show" do
      get admin_board_column_path(@column)
      assert_response :success
    end

    test "board_tasks#index" do
      get admin_board_tasks_path
      assert_response :success
    end

    test "board_tasks#show" do
      get admin_board_task_path(@task)
      assert_response :success
    end

    test "board_view_presets#index" do
      get admin_board_view_presets_path
      assert_response :success
    end

    test "board_view_presets#show" do
      get admin_board_view_preset_path(@preset)
      assert_response :success
    end

    test "column_transitions#index" do
      get admin_column_transitions_path
      assert_response :success
    end

    test "column_transitions#show" do
      get admin_column_transition_path(@transition)
      assert_response :success
    end

    test "column_workflow_bindings#index" do
      get admin_column_workflow_bindings_path
      assert_response :success
    end

    test "column_workflow_bindings#show" do
      get admin_column_workflow_binding_path(@binding)
      assert_response :success
    end

    test "config_items#index" do
      get admin_config_items_path
      assert_response :success
    end

    test "config_items#show" do
      get admin_config_item_path(@config_item)
      assert_response :success
    end

    test "integrations#index" do
      get admin_integrations_path
      assert_response :success
    end

    test "integrations#show" do
      get admin_integration_path(@integration)
      assert_response :success
    end

    test "mcp_servers#index" do
      get admin_mcp_servers_path
      assert_response :success
    end

    test "mcp_servers#show" do
      get admin_mcp_server_path(@mcp)
      assert_response :success
    end

    test "repositories#index" do
      get admin_repositories_path
      assert_response :success
    end

    test "repositories#show" do
      get admin_repository_path(@repository)
      assert_response :success
    end

    test "skills#index" do
      get admin_skills_path
      assert_response :success
    end

    test "skills#show" do
      get admin_skill_path(@skill)
      assert_response :success
    end

    test "tools#index" do
      get admin_tools_path
      assert_response :success
    end

    test "tools#show" do
      get admin_tool_path(@tool)
      assert_response :success
    end

    test "tool_files#index" do
      get admin_tool_files_path
      assert_response :success
    end

    test "tool_files#show" do
      get admin_tool_file_path(@tool_file)
      assert_response :success
    end

    test "workflows#index" do
      get admin_workflows_path
      assert_response :success
    end

    test "workflows#show" do
      get admin_workflow_path(@workflow)
      assert_response :success
    end

    test "workflow_runs#index" do
      get admin_workflow_runs_path
      assert_response :success
    end

    test "workflow_runs#show" do
      get admin_workflow_run_path(@workflow_run)
      assert_response :success
    end

    test "workflow_run_assets#index" do
      get admin_workflow_run_assets_path
      assert_response :success
    end

    test "workflow_run_assets#show" do
      get admin_workflow_run_asset_path(@wra)
      assert_response :success
    end

    test "steps#index" do
      get admin_steps_path
      assert_response :success
    end

    test "steps#show" do
      get admin_step_path(@step)
      assert_response :success
    end

    test "step_runs#index" do
      get admin_step_runs_path
      assert_response :success
    end

    test "step_runs#show" do
      get admin_step_run_path(@step_run)
      assert_response :success
    end

    test "sub_steps#index" do
      get admin_sub_steps_path
      assert_response :success
    end

    test "sub_steps#show" do
      get admin_sub_step_path(@sub_step)
      assert_response :success
    end

    test "sub_step_runs#index" do
      get admin_sub_step_runs_path
      assert_response :success
    end

    test "sub_step_runs#show" do
      get admin_sub_step_run_path(@sub_step_run)
      assert_response :success
    end

    test "task_comments#index" do
      get admin_task_comments_path
      assert_response :success
    end

    test "task_comments#show" do
      get admin_task_comment_path(@task_comment)
      assert_response :success
    end

    test "task_assets#index" do
      get admin_task_assets_path
      assert_response :success
    end

    test "task_assets#show" do
      get admin_task_asset_path(@task_asset)
      assert_response :success
    end

    test "usage_statistics#index" do
      get admin_usage_statistics_path
      assert_response :success
    end

    test "usage_statistics#show" do
      get admin_usage_statistic_path(@usage)
      assert_response :success
    end

    test "namespace_resource_quotas#index" do
      get admin_namespace_resource_quotas_path
      assert_response :success
    end

    test "namespace_resource_quotas#show" do
      get admin_namespace_resource_quota_path(@quota)
      assert_response :success
    end
  end
end
