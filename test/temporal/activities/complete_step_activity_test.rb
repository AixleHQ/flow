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

        result = run_activity(CompleteStepActivity, { "step_run_id" => step_run.id })

        assert result["quota_error"]
        assert result["failed"]
        refute result["valid"]

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

        result = run_activity(CompleteStepActivity, { "step_run_id" => step_run.id })

        assert_nil result["quota_error"]
        assert result["failed"]

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

        result = run_activity(CompleteStepActivity, { "step_run_id" => step_run.id })

        assert result["quota_error"]
        step_run.reload
        assert_equal "failed", step_run.state
        assert_equal "quota_exceeded", step_run.error_category
        @run.reload
        assert_equal "quota_exceeded", @run.failure_reason
        assert_equal credential.id, @run.failed_agent_credential_id
      end

      test "detects quota error even when the terminal log is wrapped in ANSI escape codes" do
        session = create(:terminal_session,
          user: @user,
          agent_type: "cursor_cli",
          session_type: :workflow_step,
          state: "finished")
        SessionLog.create!(
          terminal_session: session,
          name: "terminal_output.log",
          file: StringIO.new("\e[1m\e[31mError: You've reached your normal usage limit.\e[0m\r\n"),
          file_size: 60,
          content_type: "text/plain; charset=utf-8"
        )
        create(:agent_credential, user: @user, agent_type: "cursor_cli")
        step_run = create(:step_run, workflow_run: @run, step: @step, terminal_session: session)

        result = run_activity(CompleteStepActivity, { "step_run_id" => step_run.id })

        assert result["quota_error"]
        assert_equal "quota_exceeded", step_run.reload.error_category
      end

      test "handles session with no matching credential gracefully" do
        session = create(:terminal_session, :failed,
          user: @user,
          agent_type: "codex",
          error_message: "You exceeded your current quota")
        step_run = create(:step_run, workflow_run: @run, step: @step, terminal_session: session)

        result = run_activity(CompleteStepActivity, { "step_run_id" => step_run.id })

        assert result["quota_error"]
        @run.reload
        assert_equal "quota_exceeded", @run.failure_reason
        assert_nil @run.failed_agent_credential_id
      end

      # --- success path ---

      test "completes step with no output specs and no assets" do
        session = create(:terminal_session, :collected,
          user: @user,
          agent_type: "claude_code",
          session_type: :workflow_step)
        step_run = create(:step_run, :running, workflow_run: @run, step: @step, terminal_session: session)

        result = run_activity(CompleteStepActivity, { "step_run_id" => step_run.id })

        assert result["valid"]
        assert_nil result["failed"]
        assert_nil result["quota_error"]
        assert_equal step_run.id, result["step_run_id"]
        assert_equal @step.id, result["step_id"]
        assert_equal @run.id, result["workflow_run_id"]
        assert_equal 0, result["assets_collected"]

        step_run.reload
        assert_equal "completed", step_run.state
        assert_not_nil step_run.completed_at
        assert_nil step_run.error_message

        @run.reload
        assert_nil @run.failure_reason
      end

      test "completes step and counts produced assets" do
        session = create(:terminal_session, :collected,
          user: @user,
          agent_type: "claude_code",
          session_type: :workflow_step)
        step_run = create(:step_run, :running, workflow_run: @run, step: @step, terminal_session: session)
        create(:workflow_run_asset, workflow_run: @run, produced_by_step_run: step_run, name: "one.md")
        create(:workflow_run_asset, workflow_run: @run, produced_by_step_run: step_run, name: "two.md")
        # Asset produced by a different step must not be counted.
        other_step_run = create(:step_run, workflow_run: @run, step: @step)
        create(:workflow_run_asset, workflow_run: @run, produced_by_step_run: other_step_run, name: "other.md")

        result = run_activity(CompleteStepActivity, { "step_run_id" => step_run.id })

        assert result["valid"]
        assert_equal 2, result["assets_collected"]

        step_run.reload
        assert_equal "completed", step_run.state
      end

      test "completes step when output_asset_specs are satisfied" do
        step = create(:step, workflow: @workflow,
          output_asset_specs: [ { "name" => "report.md", "required" => true } ])
        session = create(:terminal_session, :collected,
          user: @user,
          agent_type: "claude_code",
          session_type: :workflow_step)
        step_run = create(:step_run, :running, workflow_run: @run, step: step, terminal_session: session)
        create(:workflow_run_asset, workflow_run: @run, produced_by_step_run: step_run, name: "report.md")

        result = run_activity(CompleteStepActivity, { "step_run_id" => step_run.id })

        assert result["valid"]
        assert_nil result["validation_errors"]
        assert_equal 1, result["assets_collected"]

        step_run.reload
        assert_equal "completed", step_run.state
      end

      test "completes step when there is no terminal session" do
        step_run = create(:step_run, :running, workflow_run: @run, step: @step, terminal_session: nil)

        result = run_activity(CompleteStepActivity, { "step_run_id" => step_run.id })

        assert result["valid"]
        assert_nil result["failed"]
        assert_equal 0, result["assets_collected"]

        step_run.reload
        assert_equal "completed", step_run.state
        assert_not_nil step_run.completed_at
      end
    end
  end
end
