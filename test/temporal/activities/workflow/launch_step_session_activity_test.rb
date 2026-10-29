# frozen_string_literal: true

require "test_helper"

class Activities::Workflow::LaunchStepSessionActivityTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @runner = create(:runner, company: @company, created_by: @user, name: "Prod VPC")
    workflow = create(:workflow, scope: @project)
    board = create(:board, project: @project)
    @task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    @run = create(:workflow_run, :running, workflow: workflow, project: @project, user: @user, runner: @runner,
                                           board_task: @task)
    @step_run = create(:step_run, workflow_run: @run, step: create(:step, workflow: workflow))
  end

  test "a refused runner fails the step and the run's reason, comments on the task, and is not retried" do
    @runner.disable!

    error = with_feature(:external_runners, true, company: @company) do
      assert_raises(Temporalio::Error::ApplicationError) do
        run_activity(Activities::Workflow::LaunchStepSessionActivity, { "step_run_id" => @step_run.id })
      end
    end

    message = "Runner \"Prod VPC\" is disabled. Re-enable it or pick another runner on the workflow."
    assert error.non_retryable
    assert_equal "RunnerRefused", error.type
    assert_equal [ "failed", message ], [ @step_run.reload.state, @step_run.error_message ]
    assert_equal "runner_unavailable", @run.reload.failure_reason
    assert_match(/failed: #{Regexp.escape(message)}/, @task.task_comments.sole.body)
    assert_nil @step_run.terminal_session
  end
end
