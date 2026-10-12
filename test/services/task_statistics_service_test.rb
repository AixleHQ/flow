# frozen_string_literal: true

require "test_helper"

class TaskStatisticsServiceTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    @user = create(:user, :admin, company: company)
    @project = create(:project, company: company, owner: @user)
    board = create(:board, project: @project)
    @task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    @workflow = create(:workflow, scope: @project, name: "Review")
  end

  test "run time counts each run once, from its first step leaving the queue" do
    freeze_time do
      run = create(:workflow_run, :completed, workflow: @workflow, project: @project, user: @user, board_task: @task,
                                              started_at: 1.hour.ago, execution_started_at: 10.minutes.ago,
                                              completed_at: Time.current)
      2.times { create(:step_run, workflow_run: run, step: create(:step, workflow: @workflow)) }
      create(:workflow_run, :cancelled, workflow: @workflow, project: @project, user: @user, board_task: @task,
                                        started_at: 1.hour.ago, execution_started_at: nil, completed_at: Time.current)

      result = TaskStatisticsService.new(task: @task).call

      assert_equal 10.minutes.to_i, result.time_totals[:total_duration_seconds]
      assert_equal [ [ "Review", 10.minutes.to_i ] ], result.workflow_breakdowns.map { |w| [ w.workflow_name, w.duration_seconds ] }
    end
  end
end
