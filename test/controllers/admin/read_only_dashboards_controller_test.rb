# frozen_string_literal: true

require "test_helper"

module Admin
  class ReadOnlyDashboardsControllerTest < Admin::ActionControllerTestCase
    # Shared fixtures for all read-only admin dashboards.
    # Each test below switches @controller to the relevant controller class,
    # then exercises index and show.

    setup do
      @company = create(:company)
      @user = create(:user, :onboarding_completed, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @board = create(:board, project: @project)
      @column = create(:board_column, board: @board)
      @task = create(:board_task, board: @board, board_column: @column)
      @workflow = create(:workflow, scope: @company)
      @step = create(:step, workflow: @workflow)
      @sub_step = create(:sub_step, step: @step)
      @workflow_run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
      @step_run = create(:step_run, workflow_run: @workflow_run, step: @step)
      @sub_step_run = create(:sub_step_run, step_run: @step_run, sub_step: @sub_step)
      @wra = create(:workflow_run_asset, workflow_run: @workflow_run)
      @tool = create(:tool, :with_company_scope, scope: @company)
      @tool_file = @tool.tool_files.create!(path: "/workspace/x.rb", content: "1")
      @skill = create(:skill, :with_company_scope, scope: @company)
      @mcp = create(:mcp_server, scope: @company, kind: :custom)
      @integration = create(:integration, company: @company, connected_by: @user)
      @repository = create(:repository, integration: @integration, scope: @company)
      @config_item = create(:config_item, scope: @company)
      @agent = Agent.create!(name: "testagent", title: "Test", persona: "p", source: :custom, scope: @company)
      @terminal_session = create(:terminal_session, user: @user, project: @project)
      @tool_result = create(:tool_result, terminal_session: @terminal_session)
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

      @super_admin = create(:user, :super_admin)
      sign_in @super_admin
    end

    # -- Agents --

    test "agents#index" do
      use_controller Admin::AgentsController
      get :index
      assert_response :success
    end

    test "agents#show" do
      use_controller Admin::AgentsController
      get :show, params: { id: @agent.id }
      assert_response :success
    end

    # -- Boards --

    test "boards#index" do
      use_controller Admin::BoardsController
      get :index
      assert_response :success
    end

    test "boards#show" do
      use_controller Admin::BoardsController
      get :show, params: { id: @board.id }
      assert_response :success
    end

    # -- BoardActivities --

    test "board_activities#index" do
      use_controller Admin::BoardActivitiesController
      get :index
      assert_response :success
    end

    test "board_activities#show" do
      use_controller Admin::BoardActivitiesController
      get :show, params: { id: @activity.id }
      assert_response :success
    end

    # -- BoardColumns --

    test "board_columns#index" do
      use_controller Admin::BoardColumnsController
      get :index
      assert_response :success
    end

    test "board_columns#show" do
      use_controller Admin::BoardColumnsController
      get :show, params: { id: @column.id }
      assert_response :success
    end

    # -- BoardTasks --

    test "board_tasks#index" do
      use_controller Admin::BoardTasksController
      get :index
      assert_response :success
    end

    test "board_tasks#show" do
      use_controller Admin::BoardTasksController
      get :show, params: { id: @task.id }
      assert_response :success
    end

    # -- BoardViewPresets --

    test "board_view_presets#index" do
      use_controller Admin::BoardViewPresetsController
      get :index
      assert_response :success
    end

    test "board_view_presets#show" do
      use_controller Admin::BoardViewPresetsController
      get :show, params: { id: @preset.id }
      assert_response :success
    end

    # -- ColumnTransitions --

    test "column_transitions#index" do
      use_controller Admin::ColumnTransitionsController
      get :index
      assert_response :success
    end

    test "column_transitions#show" do
      use_controller Admin::ColumnTransitionsController
      get :show, params: { id: @transition.id }
      assert_response :success
    end

    # -- ColumnWorkflowBindings --

    test "column_workflow_bindings#index" do
      use_controller Admin::ColumnWorkflowBindingsController
      get :index
      assert_response :success
    end

    test "column_workflow_bindings#show" do
      use_controller Admin::ColumnWorkflowBindingsController
      get :show, params: { id: @binding.id }
      assert_response :success
    end

    # -- ConfigItems --

    test "config_items#index" do
      use_controller Admin::ConfigItemsController
      get :index
      assert_response :success
    end

    test "config_items#show" do
      use_controller Admin::ConfigItemsController
      get :show, params: { id: @config_item.id }
      assert_response :success
    end

    # -- Integrations --

    test "integrations#index" do
      use_controller Admin::IntegrationsController
      get :index
      assert_response :success
    end

    test "integrations#show" do
      use_controller Admin::IntegrationsController
      get :show, params: { id: @integration.id }
      assert_response :success
    end

    # -- MCPServers --

    test "mcp_servers#index" do
      use_controller Admin::MCPServersController
      get :index
      assert_response :success
    end

    test "mcp_servers#show" do
      use_controller Admin::MCPServersController
      get :show, params: { id: @mcp.id }
      assert_response :success
    end

    # -- Repositories --

    test "repositories#index" do
      use_controller Admin::RepositoriesController
      get :index
      assert_response :success
    end

    test "repositories#show" do
      use_controller Admin::RepositoriesController
      get :show, params: { id: @repository.id }
      assert_response :success
    end

    # -- Skills --

    test "skills#index" do
      use_controller Admin::SkillsController
      get :index
      assert_response :success
    end

    test "skills#show" do
      use_controller Admin::SkillsController
      get :show, params: { id: @skill.id }
      assert_response :success
    end

    # -- Tools --

    test "tools#index" do
      use_controller Admin::ToolsController
      get :index
      assert_response :success
    end

    test "tools#show" do
      use_controller Admin::ToolsController
      get :show, params: { id: @tool.id }
      assert_response :success
    end

    # -- ToolFiles --

    test "tool_files#index" do
      use_controller Admin::ToolFilesController
      get :index
      assert_response :success
    end

    test "tool_files#show" do
      use_controller Admin::ToolFilesController
      get :show, params: { id: @tool_file.id }
      assert_response :success
    end

    # -- ToolResults --

    test "tool_results#index" do
      use_controller Admin::ToolResultsController
      get :index
      assert_response :success
    end

    test "tool_results#show" do
      use_controller Admin::ToolResultsController
      get :show, params: { id: @tool_result.id }
      assert_response :success
    end

    # -- Workflows --

    test "workflows#index" do
      use_controller Admin::WorkflowsController
      get :index
      assert_response :success
    end

    test "workflows#show" do
      use_controller Admin::WorkflowsController
      get :show, params: { id: @workflow.id }
      assert_response :success
    end

    # -- WorkflowRuns --

    test "workflow_runs#index" do
      use_controller Admin::WorkflowRunsController
      get :index
      assert_response :success
    end

    test "workflow_runs#show" do
      use_controller Admin::WorkflowRunsController
      get :show, params: { id: @workflow_run.id }
      assert_response :success
    end

    # -- WorkflowRunAssets --

    test "workflow_run_assets#index" do
      use_controller Admin::WorkflowRunAssetsController
      get :index
      assert_response :success
    end

    test "workflow_run_assets#show" do
      use_controller Admin::WorkflowRunAssetsController
      get :show, params: { id: @wra.id }
      assert_response :success
    end

    # -- Steps --

    test "steps#index" do
      use_controller Admin::StepsController
      get :index
      assert_response :success
    end

    test "steps#show" do
      use_controller Admin::StepsController
      get :show, params: { id: @step.id }
      assert_response :success
    end

    # -- StepRuns --

    test "step_runs#index" do
      use_controller Admin::StepRunsController
      get :index
      assert_response :success
    end

    test "step_runs#show" do
      use_controller Admin::StepRunsController
      get :show, params: { id: @step_run.id }
      assert_response :success
    end

    # -- SubSteps --

    test "sub_steps#index" do
      use_controller Admin::SubStepsController
      get :index
      assert_response :success
    end

    test "sub_steps#show" do
      use_controller Admin::SubStepsController
      get :show, params: { id: @sub_step.id }
      assert_response :success
    end

    # -- SubStepRuns --

    test "sub_step_runs#index" do
      use_controller Admin::SubStepRunsController
      get :index
      assert_response :success
    end

    test "sub_step_runs#show" do
      use_controller Admin::SubStepRunsController
      get :show, params: { id: @sub_step_run.id }
      assert_response :success
    end

    # -- TaskComments --

    test "task_comments#index" do
      use_controller Admin::TaskCommentsController
      get :index
      assert_response :success
    end

    test "task_comments#show" do
      use_controller Admin::TaskCommentsController
      get :show, params: { id: @task_comment.id }
      assert_response :success
    end

    # -- TaskAssets --

    test "task_assets#index" do
      use_controller Admin::TaskAssetsController
      get :index
      assert_response :success
    end

    test "task_assets#show" do
      use_controller Admin::TaskAssetsController
      get :show, params: { id: @task_asset.id }
      assert_response :success
    end

    # -- UsageStatistics --

    test "usage_statistics#index" do
      use_controller Admin::UsageStatisticsController
      get :index
      assert_response :success
    end

    test "usage_statistics#show" do
      use_controller Admin::UsageStatisticsController
      get :show, params: { id: @usage.id }
      assert_response :success
    end

    private

    def use_controller(klass)
      @controller = klass.new
    end
  end
end
