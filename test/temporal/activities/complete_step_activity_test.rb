# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class CompleteStepActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, :admin, company: @company)
        @project = create(:project, company: @company, owner: @user)
        @workflow = create(:workflow, scope: @company)
        @step = create(:step, workflow: @workflow)
        @run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)
        @credential = create(:agent_credential, user: @user, agent_type: "claude_code")
        @activity = CompleteStepActivity.new

        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
        Rails.logger.stubs(:error)
      end

      # --- quota error path ---

      test "detects quota error from failed session and marks step with error_category" do
        session = create(:terminal_session, :failed,
          user: @user,
          agent_type: "claude_code",
          error_message: "Your credit balance is too low to complete this request")
        step_run = create(:step_run, workflow_run: @run, step: @step, terminal_session: session)

        result = @activity.execute({ "step_run_id" => step_run.id })

        assert_equal true, result["quota_error"]
        assert_equal true, result["failed"]
        assert_equal false, result["valid"]

        step_run.reload
        assert_equal "failed", step_run.state
        assert_equal "quota_exceeded", step_run.error_category

        @run.reload
        assert_equal "quota_exceeded", @run.failure_reason
        assert_equal @credential.id, @run.failed_agent_credential_id
      end

      test "does not set quota_error for generic session failure" do
        session = create(:terminal_session, :failed,
          user: @user,
          agent_type: "claude_code",
          error_message: "Container exited unexpectedly")
        step_run = create(:step_run, workflow_run: @run, step: @step, terminal_session: session)

        result = @activity.execute({ "step_run_id" => step_run.id })

        assert_nil result["quota_error"]
        assert_equal true, result["failed"]

        step_run.reload
        assert_nil step_run.error_category
      end

      test "detects cursor usage limit from terminal log when session finished" do
        session = create(:terminal_session,
          user: @user,
          agent_type: "cursor_cli",
          session_type: :workflow_step,
          state: "finished")
        SessionLog.create!(
          terminal_session: session,
          name: "terminal_output.log",
          file: StringIO.new(<<~TEXT),
            agent --force
            Error: You've reached your normal usage limit.
            You're out of usage. Ask your admin to increase your limit to continue.
          TEXT
          file_size: 120,
          content_type: "text/plain"
        )
        credential = create(:agent_credential, user: @user, agent_type: "cursor_cli")
        step_run = create(:step_run, workflow_run: @run, step: @step, terminal_session: session)

        result = @activity.execute({ "step_run_id" => step_run.id })

        assert_equal true, result["quota_error"]
        step_run.reload
        assert_equal "failed", step_run.state
        assert_equal "quota_exceeded", step_run.error_category
        @run.reload
        assert_equal "quota_exceeded", @run.failure_reason
        assert_equal credential.id, @run.failed_agent_credential_id
      end

      test "handles session with no matching credential gracefully" do
        session = create(:terminal_session, :failed,
          user: @user,
          agent_type: "codex",
          error_message: "You exceeded your current quota")
        step_run = create(:step_run, workflow_run: @run, step: @step, terminal_session: session)

        result = @activity.execute({ "step_run_id" => step_run.id })

        assert_equal true, result["quota_error"]
        @run.reload
        assert_equal "quota_exceeded", @run.failure_reason
        assert_nil @run.failed_agent_credential_id
      end
    end
  end
end
