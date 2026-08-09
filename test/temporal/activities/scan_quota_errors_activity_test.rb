# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class ScanQuotaErrorsActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, :admin, company: @company)
        @runtime_mock = mock("runtime")
        ContainerRuntime.stubs(:build).returns(@runtime_mock)
        @runtime_mock.stubs(:resolve_container).returns(nil)
        @runtime_mock.stubs(:exec!).returns([ [], [], 0 ])

        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
        Rails.logger.stubs(:error)
      end

      test "fails ready workflow_step session with quota error in error_message" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-abc",
          started_at: 3.minutes.ago,
          error_message: "Credit balance too low · Add funds: https://platform.claude.com/settings/billing")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        session.reload
        assert_equal "failed", session.state
        assert_equal "Credit balance too low · Add funds: https://platform.claude.com/settings/billing",
                     session.error_message
      end

      test "fails ready session when quota error appears only in live terminal output" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-live",
          started_at: 3.minutes.ago,
          error_message: nil)

        container = mock("container")
        @runtime_mock.stubs(:resolve_container).with("container-live").returns(container)
        @runtime_mock.stubs(:exec!).returns([
          [ "Credit balance too low · Add funds: https://platform.claude.com/settings/billing\n" ],
          [],
          0
        ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        session.reload
        assert_equal "failed", session.state
        assert_equal "Credit balance too low · Add funds: https://platform.claude.com/settings/billing",
                     session.error_message
      end

      test "stores short error_message when terminal capture includes shell prompt noise" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-noisy",
          started_at: 3.minutes.ago,
          error_message: nil)

        container = mock("container")
        @runtime_mock.stubs(:resolve_container).with("container-noisy").returns(container)
        @runtime_mock.stubs(:exec!).returns([
          [
            "claude@d683c38e063a:/workspace$",
            "claude \"$AGENT_PROMPT\"",
            "Credit balance too low · Add funds: https://platform.claude.com/settings/billing"
          ],
          [],
          0
        ])

        run_activity(ScanQuotaErrorsActivity)

        session.reload
        assert_equal "Credit balance too low · Add funds: https://platform.claude.com/settings/billing",
                     session.error_message
      end

      test "fails ready cursor_cli session with usage limit in terminal output" do
        session = create(:terminal_session,
          user: @user,
          agent_type: "cursor_cli",
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-cursor",
          started_at: 3.minutes.ago,
          error_message: nil)

        container = mock("container")
        @runtime_mock.stubs(:resolve_container).with("container-cursor").returns(container)
        @runtime_mock.stubs(:exec!).returns([
          [
            "Error: You've reached your normal usage limit.\n",
            "You're out of usage. Ask your admin to increase your limit to continue.\n"
          ],
          [],
          0
        ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        session.reload
        assert_equal "failed", session.state
        assert_equal "Error: You've reached your normal usage limit.", session.error_message
      end

      test "signals the failed session's own container workflow so its cleanup runs" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-quota",
          started_at: 3.minutes.ago,
          temporal_workflow_id: "wf-quota",
          error_message: "Credit balance too low · Add funds: https://platform.claude.com/settings/billing")

        # Failing the row alone left this execution parked on its `container_finished`
        # await for 23 hours, so the pod, Service and IngressRoute were never
        # reclaimed. It is the same leak the dead-container watchdog had to avoid.
        TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        assert_equal "failed", session.reload.state
      end

      test "skips a session whose container is unreachable instead of scanning it" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-gone",
          started_at: 3.minutes.ago,
          error_message: nil)

        container = mock("container")
        @runtime_mock.stubs(:resolve_container).with("container-gone").returns(container)
        @runtime_mock.stubs(:exec!).raises(
          ContainerRuntime::ContainerUnreachableError.new(
            status_code: 404, container_identifier: "aixle/terminal-gone"
          )
        )

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        assert_equal 1, result[:unreachable]
        session.reload
        assert_equal "ready", session.state
        assert_nil session.error_message
      end

      test "still fails a session when the command runs and merely exits non-zero" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-busy",
          started_at: 3.minutes.ago,
          error_message: "Credit balance too low")

        container = mock("container")
        @runtime_mock.stubs(:resolve_container).with("container-busy").returns(container)
        @runtime_mock.stubs(:exec!).returns([ [], [ "no server running on /tmp/tmux-0/default\n" ], 1 ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        assert_equal 0, result[:unreachable]
        session.reload
        assert_equal "failed", session.state
      end

      test "does not touch sessions without quota error text" do
        session = create(:terminal_session, :running,
          user: @user,
          session_type: :workflow_step,
          started_at: 3.minutes.ago,
          error_message: "Connection refused")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "running", session.state
      end

      test "does not touch sessions younger than MIN_AGE" do
        session = create(:terminal_session, :running,
          user: @user,
          session_type: :workflow_step,
          started_at: 30.seconds.ago,
          error_message: "Credit balance too low")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "running", session.state
      end

      test "does not touch sessions without container_id" do
        session = create(:terminal_session, :running,
          user: @user,
          session_type: :workflow_step,
          container_id: nil,
          started_at: 3.minutes.ago,
          error_message: "Credit balance too low")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "running", session.state
      end

      test "does not touch non-workflow_step sessions" do
        session = create(:terminal_session, :running,
          user: @user,
          session_type: :agent_session,
          started_at: 3.minutes.ago,
          error_message: "insufficient_quota")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "running", session.state
      end

      test "returns cleaned count of 0 when no candidate sessions exist" do
        result = run_activity(ScanQuotaErrorsActivity)
        assert_equal 0, result[:cleaned]
      end
    end
  end
end
