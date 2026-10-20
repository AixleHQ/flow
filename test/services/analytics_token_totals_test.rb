# frozen_string_literal: true

require "test_helper"

class AnalyticsTokenTotalsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  [ ProjectAnalyticsService, CompanyAnalyticsService, UserAnalyticsService ].each do |service|
    test "#{service} sums every breakdown column across sessions" do
      seed_usage

      result = service.new(**arguments_for(service)).call

      assert_equal 300, result.total_tokens
      assert_equal [ 300 ], result.project_breakdowns.map(&:tokens) if result.respond_to?(:project_breakdowns)
    end

    test "#{service} returns zero tokens without sessions" do
      assert_equal 0, service.new(**arguments_for(service)).call.total_tokens
    end
  end

  [ AgentActivityService, CompanyAgentActivityService, UserAgentActivityService ].each do |service|
    test "#{service} sums every breakdown column across sessions in the same agent group" do
      seed_usage

      result = service.new(**arguments_for(service)).call

      assert_equal [ 300 ], result.sessions_by_agent.map(&:tokens)
    end
  end

  [ SessionCostTokenUsageService, CompanySessionCostTokenUsageService, UserSessionCostTokenUsageService ].each do |service|
    test "#{service} sums every breakdown column across sessions in the same time bucket" do
      freeze_time do
        seed_usage

        result = service.new(**arguments_for(service)).call

        assert_equal [ 300 ], result.time_series.map(&:total_tokens)
      end
    end

    test "#{service} returns zero tokens for a session without usage" do
      create_session

      result = service.new(**arguments_for(service)).call

      assert_equal [ 0 ], result.time_series.map(&:total_tokens)
    end
  end

  test "workflow summaries and time series sum every breakdown column across sessions" do
    freeze_time do
      seed_workflow_usage

      result = WorkflowCostAnalyticsService.new(**arguments_for(WorkflowCostAnalyticsService)).call

      assert_equal 300, result.totals[:total_tokens]
      assert_equal [ 300 ], result.workflows.map(&:total_tokens)
      assert_equal [ 300 ], result.time_series.map(&:total_tokens)
    end
  end

  test "company workflow time series sums every breakdown column across sessions" do
    freeze_time do
      seed_workflow_usage

      result = CompanyWorkflowCostAnalyticsService.new(**arguments_for(CompanyWorkflowCostAnalyticsService)).call

      assert_equal [ 300 ], result.time_series.map(&:total_tokens)
    end
  end

  test "task summary and workflow breakdown sum every breakdown column across sessions" do
    board = create(:board, project: @project)
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    seed_workflow_usage(task: task)

    result = TaskStatisticsService.new(task: task).call

    assert_equal 300, result.token_totals[:total_tokens]
    assert_equal [ 300 ], result.workflow_breakdowns.map(&:total_tokens)
  end

  private

  def arguments_for(service)
    common = { user: @user, period: "30d" }
    case service.name
    when /\AUser/
      common.merge(company: @company)
    when /\ACompany/
      common.merge(company: @company, scope: "company")
    else
      common.merge(project: @project, scope: "project")
    end
  end

  def create_session
    create(:terminal_session, user: @user, project: @project, session_type: "workflow_step")
  end

  def seed_usage
    all_columns = create_session
    input_only = create_session
    UsageStatistic.create!(terminal_session: all_columns, input_tokens: 40, output_tokens: 30,
                           cache_write_tokens: 20, cache_read_tokens: 10)
    UsageStatistic.create!(terminal_session: input_only, input_tokens: 200)
    UsageStatistic.create!(terminal_session: create_session)
    create_session
    [ all_columns, input_only ]
  end

  def seed_workflow_usage(task: nil)
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task: task)
    seed_usage.each do |session|
      create(:step_run, workflow_run: run, step: create(:step, workflow: workflow), terminal_session: session)
    end
  end
end
