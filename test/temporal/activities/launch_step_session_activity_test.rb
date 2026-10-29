# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class LaunchStepSessionActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, company: @company)
        @project = create(:project, company: @company, owner: @user)
        workflow = create(:workflow, scope: @project)
        @run = create(:workflow_run, :running, project: @project, workflow: workflow, user: @user)
        @step_run = create(:step_run, workflow_run: @run, step: create(:step, workflow: workflow))
      end

      test "an expired agent login fails the step as an expected, final error" do
        create(:agent_credential, :errored, user: @user, company: @company, agent_type: "claude_code")

        error = assert_raises(Temporalio::Error::ApplicationError) do
          run_activity(LaunchStepSessionActivity, { "step_run_id" => @step_run.id })
        end

        assert_equal "PreflightError", error.type
        assert error.non_retryable
        assert_equal TemporalExceptions::BENIGN, error.category
        assert_match(/login has expired/, @step_run.reload.error_message)
      end

      test "a run cancelled before its step launched is an expected, final error" do
        @run.update!(stop_requested_at: Time.current)

        error = assert_raises(Temporalio::Error::ApplicationError) do
          run_activity(LaunchStepSessionActivity, { "step_run_id" => @step_run.id })
        end

        assert_match(/Workflow cancelled/, error.message)
        assert error.non_retryable
        assert_equal TemporalExceptions::BENIGN, error.category
        assert_nil @step_run.reload.terminal_session
      end

      test "a refused runner fails the step and the run's reason, comments on the task, and is not retried" do
        create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
        runner = create(:runner, company: @company, created_by: @user, name: "Prod VPC")
        board = create(:board, project: @project)
        task = create(:board_task, board: board, board_column: create(:board_column, board: board))
        @run.update!(runner: runner, board_task: task)
        runner.disable!

        error = with_feature(:external_runners, true, company: @company) do
          assert_raises(Temporalio::Error::ApplicationError) do
            run_activity(LaunchStepSessionActivity, { "step_run_id" => @step_run.id })
          end
        end

        message = "Runner \"Prod VPC\" is disabled. Re-enable it or pick another runner on the workflow."
        assert error.non_retryable
        assert_equal "RunnerRefused", error.type
        assert_equal [ "failed", message ], [ @step_run.reload.state, @step_run.error_message ]
        assert_equal "runner_unavailable", @run.reload.failure_reason
        assert_match(/failed: #{Regexp.escape(message)}/, task.task_comments.sole.body)
        assert_nil @step_run.terminal_session
      end
    end
  end
end
