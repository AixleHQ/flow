# frozen_string_literal: true

require "test_helper"

# Sessions::Lifecycle, the one owner of how a TerminalSession changes state
# (docs/design/session-lifecycle.md). The compare-and-set `fail_if` has its own file.
module Sessions
  class LifecycleTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
    end

    # == finish ==

    test "finish transitions session to finishing and sends container_finished signal" do
      session = create(:terminal_session, :running, user: @user, temporal_workflow_id: "wf-123")

      TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

      Sessions::Lifecycle.finish(session)

      session.reload
      assert_equal "finishing", session.state
      assert_not_nil session.finishing_at
    end

    test "finish is idempotent across repeated calls on a running session" do
      session = create(:terminal_session, :running, user: @user, temporal_workflow_id: "wf-123")

      # A duplicate user click (or simultaneous web + mobile invocations) must
      # send the container_finished signal exactly once — extra signals would
      # cause double cleanup on the Temporal worker side.
      TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

      Sessions::Lifecycle.finish(session)
      session.reload
      first_finishing_at = session.finishing_at

      Sessions::Lifecycle.finish(session)
      session.reload

      assert_equal "finishing", session.state
      assert_equal first_finishing_at.to_i, session.finishing_at.to_i
    end

    test "finish is a no-op when session is already finishing" do
      session = create(:terminal_session, :finishing, user: @user, temporal_workflow_id: "wf-123")
      original_finishing_at = session.finishing_at

      TemporalService.expects(:send_signal).never

      Sessions::Lifecycle.finish(session)

      session.reload
      assert_equal "finishing", session.state
      assert_equal original_finishing_at.to_i, session.finishing_at.to_i
    end

    test "finish signals container workflow for workflow_step sessions" do
      workflow_run = create(:workflow_run, project: @project, user: @user)
      step = create(:step, workflow: workflow_run.workflow)
      step_run = create(:step_run, workflow_run: workflow_run, step: step)
      session = create(:terminal_session, :running, user: @user, session_type: "workflow_step",
                       temporal_workflow_id: "wf-456", project: @project)
      step_run.update!(terminal_session: session)

      # Only signals the container workflow; execution workflow is notified by before_cleanup
      TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, step_run.id).once

      Sessions::Lifecycle.finish(session)

      session.reload
      assert_equal "finishing", session.state
    end

    test "finish raises InvalidStateError for non-finishable session" do
      session = create(:terminal_session, user: @user, state: "finished")

      assert_raises(TerminalSession::InvalidStateError) do
        Sessions::Lifecycle.finish(session)
      end
    end

    test "finish without temporal workflow transitions through finishing to finished" do
      session = create(:terminal_session, :running, user: @user, temporal_workflow_id: nil)

      Sessions::Lifecycle.finish(session)

      session.reload
      assert_equal "finished", session.state
      assert_not_nil session.finishing_at
      assert_not_nil session.finished_at
    end

    # == suspend ==

    include CheckpointStorageHelper

    def interactive_session(**attrs)
      create(:terminal_session, :running, :agent_session, user: @user, project: @project, mode: "interactive",
                                                          state: "ready", temporal_workflow_id: "wf-1", **attrs)
    end

    test "suspend records the request and ends the container the way finish does" do
      use_checkpoint_storage
      session = interactive_session

      TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

      Sessions::Lifecycle.suspend(session)

      session.reload
      assert_equal "finishing", session.state
      assert Sessions::Suspension.requested?(session)
    ensure
      restore_checkpoint_storage
    end

    test "suspend refuses a session that cannot be suspended" do
      use_checkpoint_storage
      step = create(:terminal_session, :running, user: @user, project: @project, session_type: "workflow_step",
                                                 temporal_workflow_id: "wf-2")

      assert_raises(TerminalSession::InvalidStateError) { Sessions::Lifecycle.suspend(step) }
      refute Sessions::Suspension.requested?(step.reload)
    ensure
      restore_checkpoint_storage
    end

    # == cancel ==

    test "cancel stops the admission and cancels its container workflow" do
      mock_temporal_start
      create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
      session = SessionService.create_and_start(user: @user, project: @project,
                                                session_type: "agent_session", agent_type: "claude_code")

      TemporalService.expects(:cancel_workflow).with(session.workflow_id).once

      Sessions::Lifecycle.cancel(session)

      assert_equal "cancelled", session.reload.state
      assert session.session_admission.reload.stop_requested_at
    end

    test "cancel closes a session still waiting in the queue without touching Temporal" do
      with_scope_defaults(project: 1)
      create(:terminal_session, user: @user, project: @project).then { |s| SessionAdmissionService.enqueue!(s) }
      SessionAdmissionService.drain!
      waiting = create(:terminal_session, user: @user, project: @project)
      SessionAdmissionService.enqueue!(waiting)

      TemporalService.expects(:cancel_workflow).never

      Sessions::Lifecycle.cancel(waiting)

      assert_equal "cancelled", waiting.reload.state
      assert waiting.session_admission.reload.released_at
    end

    # == reset_auth ==

    test "reset_auth cancels a login in progress and its container workflow" do
      mock_temporal_start
      session = SessionService.create_and_start(user: @user, company: @company,
                                                session_type: "auth_setup", agent_type: "claude_code")
      session.start!
      session.mark_ready!

      TemporalService.expects(:cancel_workflow).with(session.workflow_id).once

      Sessions::Lifecycle.reset_auth(session)

      assert_equal "cancelled", session.reload.state
      assert session.session_admission.reload.stop_requested_at
    end

    test "reset_auth leaves a login that already ended as it is" do
      session = create(:terminal_session, :auth_setup, user: @user, company: @company, state: "failed")

      TemporalService.expects(:cancel_workflow).never

      Sessions::Lifecycle.reset_auth(session)

      assert_equal "failed", session.reload.state
    end

    # == fail ==

    test "fail records the error, fails the session and signals its container workflow" do
      session = create(:terminal_session, :running, user: @user, temporal_workflow_id: "wf-dead")

      # The container workflow ("agent-session-<id>") is the execution that owns the
      # pod: without this signal it waits out its 23-hour `container_finished`
      # timeout, its cleanup phase never runs, and the pod, Service, IngressRoute and
      # Middlewares leak for a day.
      TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

      Sessions::Lifecycle.fail(session, error_message: "Agent container vanished")

      session.reload
      assert_equal "failed", session.state
      assert_equal "Agent container vanished", session.error_message
      assert_not_nil session.finished_at
    end

    test "fail signals the container workflow as well as the parent workflow run" do
      workflow_run = create(:workflow_run, project: @project, user: @user)
      step = create(:step, workflow: workflow_run.workflow)
      step_run = create(:step_run, workflow_run: workflow_run, step: step)
      session = create(:terminal_session, :running, user: @user, session_type: "workflow_step",
                       project: @project, temporal_workflow_id: "wf-step")
      step_run.update!(terminal_session: session)

      # TerminalSession#on_failed only reaches the parent run, which completes the
      # step. That is not enough on its own — both executions must hear about it.
      TemporalService.expects(:send_signal)
        .with("workflow-execution-#{workflow_run.id}", :container_finished, step_run.id).once
      TemporalService.expects(:send_signal)
        .with(session.workflow_id, :container_finished, step_run.id).once

      Sessions::Lifecycle.fail(session, error_message: "Agent container vanished")

      assert_equal "failed", session.reload.state
    end

    test "fail fails a session that has no temporal workflow without signalling" do
      session = create(:terminal_session, :running, user: @user, temporal_workflow_id: nil)

      TemporalService.expects(:send_signal).never

      Sessions::Lifecycle.fail(session, error_message: "Agent container vanished")

      session.reload
      assert_equal "failed", session.state
      assert_equal "Agent container vanished", session.error_message
    end

    test "fail on an already failed session keeps its original error and still signals" do
      session = create(:terminal_session, :failed, user: @user, temporal_workflow_id: "wf-dead")

      # A second sweep must still be able to nudge a container workflow that is
      # somehow still running — the state transition is what is idempotent here.
      TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

      Sessions::Lifecycle.fail(session)

      session.reload
      assert_equal "failed", session.state
      assert_equal "Container failed to start", session.error_message
    end

    # == cancel of a session with no admission (design §3.2, decision 9) ==

    test "cancel fires the event for a session that was built but never admitted" do
      session = create(:terminal_session, user: @user, project: @project, state: "not_started")

      TemporalService.expects(:cancel_workflow).never

      Lifecycle.cancel(session)

      session.reload
      assert_equal "cancelled", session.state
      assert_not_nil session.finished_at
    end

    test "cancel of a session that is already cancelled does nothing" do
      session = create(:terminal_session, user: @user, project: @project, state: "not_started")
      Lifecycle.cancel(session)
      finished_at = session.reload.finished_at

      TemporalService.expects(:cancel_workflow).never
      Lifecycle.cancel(session.reload)

      assert_equal "cancelled", session.reload.state
      assert_equal finished_at, session.finished_at
    end

    test "a step session cancelled before it was admitted stays cancelled when admission meets the stopped run" do
      workflow = create(:workflow, scope: @project)
      run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
      step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))
      session = create(:terminal_session, user: @user, project: @project, session_type: "workflow_step", state: "not_started")
      step_run.update!(terminal_session: session)
      Lifecycle.cancel(session)
      run.update!(stop_requested_at: Time.current) if run.respond_to?(:stop_requested_at=)

      Lifecycle.cancel(session.reload)

      assert_equal "cancelled", session.reload.state
    end

    # == the relay's session_ended signal, whichever way a runner session leaves ready ==

    test "a runner session leaving ready through each ending sends session_ended once" do
      machine = create(:runner_environment, runner: create(:runner, :manual))
      signals = []
      Runners::RelaySignals.stubs(:session_ended).with { |id| signals << id }

      { finish: ->(s) { Lifecycle.finish(s) }, fail: ->(s) { Lifecycle.fail(s, error_message: "x") },
        cancel: ->(s) { Lifecycle.cancel(s) }, finalize: ->(s) { Lifecycle.finalize(s, error: nil) },
        suspended: ->(s) { Lifecycle.suspended(s) } }.each do |name, action|
        session = create(:runner_session, environment: machine, state: "ready")
        signals.clear

        action.call(session)

        assert_equal [ session.id ], signals, name.to_s
      end
    end

    test "finalize of a runner session that was not ready sends no session_ended" do
      machine = create(:runner_environment, runner: create(:runner, :manual))
      signals = []
      Runners::RelaySignals.stubs(:session_ended).with { |id| signals << id }
      session = create(:runner_session, environment: machine, state: "running")

      Lifecycle.finalize(session, error: nil)
      Lifecycle.finalize(session, error: nil)

      assert_empty signals
    end

    test "a runner session that was not ready sends no session_ended" do
      machine = create(:runner_environment, runner: create(:runner, :manual))
      signals = []
      Runners::RelaySignals.stubs(:session_ended).with { |id| signals << id }
      session = create(:runner_session, environment: machine, state: "running")

      Lifecycle.transition!(session, :fail)

      assert_empty signals
    end

    test "a hosted session leaving ready sends no session_ended" do
      signals = []
      Runners::RelaySignals.stubs(:session_ended).with { |id| signals << id }
      session = create(:terminal_session, user: @user, state: "ready")

      Lifecycle.transition!(session, :fail)

      assert_empty signals
    end

    test "session_ended goes out after the commit, never on a rollback" do
      machine = create(:runner_environment, runner: create(:runner, :manual))
      signals = []
      Runners::RelaySignals.stubs(:session_ended).with { |id| signals << id }
      session = create(:runner_session, environment: machine, state: "ready")

      ActiveRecord::Base.transaction do
        Lifecycle.transition!(session, :fail)
        assert_empty signals
        raise ActiveRecord::Rollback
      end

      assert_empty signals
    end

    # == waking the parent run ==

    def step_session(state:)
      workflow = create(:workflow, scope: @project)
      run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
      step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))
      session = create(:terminal_session, user: @user, project: @project, session_type: "workflow_step", state: state)
      step_run.update!(terminal_session: session)
      [ session, step_run, run ]
    end

    test "each ending event wakes the run once, after the commit" do
      { finish: "finishing", fail: "running", cancel: "running",
        finish_without_request: "running" }.each do |event, from|
        session, step_run, = step_session(state: from)
        WorkflowService.expects(:notify_container_finished).with(step_run: step_run).once

        Lifecycle.transition!(session, event)
      end
    end

    test "expire_suspended_step wakes the run once" do
      session, step_run, = step_session(state: "suspended")
      WorkflowService.expects(:notify_container_finished).with(step_run: step_run).once

      Lifecycle.transition!(session, :expire_suspended_step)
    end

    test "a move that does not end the session wakes nobody" do
      %i[start_finishing mark_ready].each do |event|
        session, = step_session(state: "running")
        WorkflowService.expects(:notify_container_finished).never

        Lifecycle.transition!(session, event)
      end
    end

    test "notify: false keeps an ending from waking the run" do
      session, = step_session(state: "running")
      WorkflowService.expects(:notify_container_finished).never

      Lifecycle.transition!(session, :fail, notify: false)
    end

    test "a run whose stop was requested is not woken" do
      session, _step_run, run = step_session(state: "running")
      run.update!(stop_requested_at: Time.current)
      WorkflowService.expects(:notify_container_finished).never

      Lifecycle.transition!(session, :cancel)
    end

    test "a rolled-back ending wakes nobody" do
      session, = step_session(state: "running")
      WorkflowService.expects(:notify_container_finished).never

      ActiveRecord::Base.transaction do
        Lifecycle.transition!(session, :fail)
        raise ActiveRecord::Rollback
      end
    end

    # == the run's execution start ==

    test "start of a workflow step records the run's execution start, once" do
      session, _step_run, run = step_session(state: "queued")

      Lifecycle.transition!(session, :start)

      assert_equal session.reload.started_at.to_i, run.reload.execution_started_at.to_i
      first = run.execution_started_at
      other = create(:terminal_session, user: @user, project: @project, session_type: "workflow_step", state: "queued")
      create(:step_run, workflow_run: run, step: create(:step, workflow: run.workflow), terminal_session: other)
      Lifecycle.transition!(other, :start)
      assert_equal first, run.reload.execution_started_at
    end

    test "start of a session that is not a workflow step touches no run" do
      session = create(:terminal_session, user: @user, state: "not_started")

      assert_nothing_raised { Lifecycle.transition!(session, :start) }
    end

    # == restoring the suspended session ==

    test "mark_ready of a session that continues a suspended one marks that one restored" do
      origin = create(:terminal_session, user: @user, state: "suspended")
      session = create(:terminal_session, user: @user, state: "running", restored_from_session: origin)

      Lifecycle.transition!(session, :mark_ready)

      assert_equal "restored", origin.reload.state
    end

    test "mark_ready of an ordinary session restores nothing" do
      session = create(:terminal_session, user: @user, state: "running")
      Lifecycle.expects(:restored).never

      Lifecycle.transition!(session, :mark_ready)
    end

    # == the guards ==

    test "a direct write of state raises" do
      session = create(:terminal_session, user: @user)

      assert_raises(AASM::NoDirectAssignmentError) { session.update!(state: "finished") }
      assert_raises(AASM::NoDirectAssignmentError) { session.state = "finished" }
      assert_equal "not_started", session.reload.state
    end
  end
end
