# frozen_string_literal: true

require "test_helper"

module Activities
  class CleanupStaleSessionsActivityTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @activity = CleanupStaleSessionsActivity.new

      @runtime_mock = mock("runtime")
      ContainerRuntime.stubs(:build).returns(@runtime_mock)
      @runtime_mock.stubs(:resolve_container).returns(nil)

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)

      ContainerWorkflowService.stubs(:cancel_workflow).returns({ ok: true })
    end

    # == Container Gone → fail! ==

    test "fails started session when container is gone" do
      stale = create(:terminal_session, :started, user: @user,
        started_at: 1.hour.ago, temporal_workflow_id: "wf-stale")
      @runtime_mock.stubs(:resolve_container).with(stale.container_id).returns(nil)

      result = @activity.run

      assert_equal 1, result[:cleaned_started]
      stale.reload
      assert_equal "failed", stale.state
      assert_nil stale.container_id
      assert_match(/workflow ended without cleanup/, stale.error_message)
    end

    test "fails started session without started_at using created_at" do
      stale = create(:terminal_session, user: @user, state: "started",
        started_at: nil, created_at: 1.hour.ago)

      result = @activity.run

      assert_equal 1, result[:cleaned_started]
      stale.reload
      assert_equal "failed", stale.state
    end

    test "does not clean up recently started sessions" do
      recent = create(:terminal_session, :started, user: @user,
        started_at: 5.minutes.ago)

      result = @activity.run

      assert_equal 0, result[:cleaned_started]
      recent.reload
      assert_equal "started", recent.state
    end

    test "fails running session when container is gone" do
      stale = create(:terminal_session, :running, user: @user,
        started_at: 26.hours.ago, temporal_workflow_id: "wf-running")
      @runtime_mock.stubs(:resolve_container).with(stale.container_id).returns(nil)

      result = @activity.run

      assert_equal 1, result[:cleaned_running]
      stale.reload
      assert_equal "failed", stale.state
      assert_nil stale.container_id
    end

    test "does not clean up running sessions within threshold" do
      active = create(:terminal_session, :running, user: @user,
        started_at: 10.hours.ago)

      result = @activity.run

      assert_equal 0, result[:cleaned_running]
      active.reload
      assert_equal "running", active.state
    end

    # == Container Alive → full cleanup + collect ==

    test "performs full cleanup and collects when container is alive" do
      stale = create(:terminal_session, :running, user: @user,
        session_type: "agent_session", started_at: 26.hours.ago,
        temporal_workflow_id: "wf-alive")

      container_mock = mock("container")
      @runtime_mock.stubs(:resolve_container).with(stale.container_id).returns(container_mock)

      strategy_mock = mock("strategy")
      strategy_mock.expects(:before_cleanup).once
      strategy_mock.expects(:cleanup).returns({ status: :cleaned_up })
      TerminalSession.any_instance.stubs(:strategy).returns(strategy_mock)

      result = @activity.run

      assert_equal 1, result[:cleaned_running]
      stale.reload
      assert_equal "collected", stale.state
      assert_nil stale.container_id
    end

    test "performs full cleanup for auth_setup sessions" do
      stale = create(:terminal_session, :running, user: @user,
        session_type: "auth_setup", started_at: 26.hours.ago)

      container_mock = mock("container")
      @runtime_mock.stubs(:resolve_container).with(stale.container_id).returns(container_mock)

      strategy_mock = mock("strategy")
      strategy_mock.expects(:before_cleanup).once
      strategy_mock.expects(:cleanup).returns({ status: :cleaned_up })
      TerminalSession.any_instance.stubs(:strategy).returns(strategy_mock)

      result = @activity.run

      assert_equal 1, result[:cleaned_running]
      stale.reload
      assert_equal "collected", stale.state
    end

    test "falls back to fail when full cleanup raises" do
      stale = create(:terminal_session, :running, user: @user,
        session_type: "agent_session", started_at: 26.hours.ago)

      container_mock = mock("container")
      @runtime_mock.stubs(:resolve_container).with(stale.container_id).returns(container_mock)

      strategy_mock = mock("strategy")
      strategy_mock.stubs(:before_cleanup).raises(StandardError.new("container crashed"))
      TerminalSession.any_instance.stubs(:strategy).returns(strategy_mock)

      result = @activity.run

      assert_equal 1, result[:cleaned_running]
      stale.reload
      assert_equal "failed", stale.state
      assert_match(/cleanup failed/, stale.error_message)
    end

    # == Workflow Cancellation ==

    test "attempts to cancel Temporal workflow" do
      stale = create(:terminal_session, :started, user: @user,
        started_at: 1.hour.ago, temporal_workflow_id: "wf-to-cancel")

      ContainerWorkflowService.expects(:cancel_workflow).with("wf-to-cancel").returns({ ok: true })

      @activity.run
    end

    test "skips cancellation when no workflow_id" do
      create(:terminal_session, :started, user: @user,
        started_at: 1.hour.ago, temporal_workflow_id: nil)

      ContainerWorkflowService.expects(:cancel_workflow).never

      result = @activity.run

      assert_equal 1, result[:cleaned_started]
    end

    test "continues cleanup even if workflow cancellation fails" do
      stale = create(:terminal_session, :started, user: @user,
        started_at: 1.hour.ago, temporal_workflow_id: "wf-gone")

      ContainerWorkflowService.stubs(:cancel_workflow)
        .raises(StandardError.new("workflow not found"))

      result = @activity.run

      assert_equal 1, result[:cleaned_started]
      stale.reload
      assert_equal "failed", stale.state
    end

    # == Mixed Scenarios ==

    test "handles mix of alive and gone containers" do
      gone = create(:terminal_session, :started, user: @user,
        started_at: 2.hours.ago)
      @runtime_mock.stubs(:resolve_container).with(gone.container_id).returns(nil)

      alive = create(:terminal_session, :running, user: @user,
        session_type: "agent_session", started_at: 30.hours.ago)
      alive_container = mock("container")
      @runtime_mock.stubs(:resolve_container).with(alive.container_id).returns(alive_container)

      strategy_mock = mock("strategy")
      strategy_mock.expects(:before_cleanup).once
      strategy_mock.expects(:cleanup).returns({ status: :cleaned_up })
      TerminalSession.any_instance.stubs(:strategy).returns(strategy_mock)

      result = @activity.run

      assert_equal 1, result[:cleaned_started]
      assert_equal 1, result[:cleaned_running]

      gone.reload
      alive.reload
      assert_equal "failed", gone.state
      assert_equal "collected", alive.state
    end

    test "ignores sessions in terminal states" do
      create(:terminal_session, :collected, user: @user)
      create(:terminal_session, :failed, user: @user)

      result = @activity.run

      assert_equal 0, result[:cleaned_started]
      assert_equal 0, result[:cleaned_running]
    end

    test "sets finished_at on failed sessions" do
      stale = create(:terminal_session, :started, user: @user,
        started_at: 1.hour.ago, finished_at: nil)

      @activity.run

      stale.reload
      assert_equal "failed", stale.state
      assert_not_nil stale.finished_at
    end
  end
end
