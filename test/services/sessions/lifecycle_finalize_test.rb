# frozen_string_literal: true

require "test_helper"

# Sessions::Lifecycle.finalize: the final state of a session whose work is over, from
# what the runtime reported, each move being an event of the state machine
# (docs/design/session-lifecycle.md §3.4).
module Sessions
  class LifecycleFinalizeTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.companies.first)
    end

    def session_in(state, **attrs)
      create(:terminal_session, user: @user, project: @project, state: state, container_id: "ctr-1", **attrs)
    end

    # (from, outcome) pairs the machine records, with the attributes that make the session end that way.
    PAIRS = [
      [ "finishing", "finished", { finishing_at: 1.minute.ago, ready_at: 2.minutes.ago }, nil ],
      [ "not_started", "finished", {}, nil ],
      [ "queued", "finished", {}, nil ],
      [ "running", "finished", {}, nil ],
      [ "ready", "finished", {}, nil ],
      [ "not_started", "failed", {}, "boom" ],
      [ "queued", "failed", {}, "boom" ],
      [ "running", "failed", {}, "boom" ],
      [ "ready", "failed", {}, "boom" ],
      [ "finishing", "failed", { finishing_at: 1.minute.ago }, "boom" ],
      [ "finished", "failed", {}, "Output collection failed: boom" ],
      [ "not_started", "cancelled", { finishing_at: 1.minute.ago }, nil ],
      [ "queued", "cancelled", { finishing_at: 1.minute.ago }, nil ],
      [ "running", "cancelled", { finishing_at: 1.minute.ago }, nil ],
      [ "ready", "cancelled", { finishing_at: 1.minute.ago }, nil ],
      [ "finishing", "cancelled", { finishing_at: 1.minute.ago }, nil ]
    ].freeze

    PAIRS.each do |from, to, attrs, error|
      test "finalize records #{from} → #{to} with the columns a final state carries" do
        session = session_in(from, **attrs)

        Lifecycle.finalize(session, error: error)

        session.reload
        assert_equal to, session.state
        assert_not_nil session.finished_at
        assert_nil session.container_id
        assert_equal error, session.error_message
      end
    end

    test "a session that ended is recorded again without a move, and keeps when it ended" do
      %w[finished failed cancelled].each do |state|
        ended = 3.hours.ago.change(usec: 0)
        session = session_in(state, finished_at: ended)
        session.update!(error_message: "first") if state == "failed"

        Lifecycle.finalize(session, error: nil)
        Lifecycle.finalize(session, error: nil)

        session.reload
        assert_equal state, session.state
        assert_equal ended, session.finished_at
        assert_nil session.container_id
      end
    end

    test "a specific error outranks a generic one, whichever arrives last" do
      session = session_in("running", error_message: "Container failed to start")

      Lifecycle.finalize(session, error: TerminalSession::GENERIC_ERROR_MESSAGES.first)

      assert_equal "failed", session.reload.state
      assert_equal "Container failed to start", session.error_message
    end

    test "a state the machine has no move to the outcome from raises, and changes nothing" do
      session = session_in("suspended")

      assert_raises(TerminalSession::InvalidStateError) { Lifecycle.finalize(session, error: "boom") }

      assert_equal "suspended", session.reload.state
      assert_equal "ctr-1", session.container_id
    end

    test "finalize wakes nobody, and slot_released wakes the run once the reservation is back" do
      run = create(:workflow_run, project: @project, user: @user)
      step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: run.workflow))
      session = session_in("running", session_type: "workflow_step")
      step_run.update!(terminal_session: session)

      WorkflowService.expects(:notify_container_finished).never
      Lifecycle.finalize(session, error: nil)

      assert_equal "finished", session.reload.state
      WorkflowService.unstub(:notify_container_finished)
      WorkflowService.expects(:notify_container_finished).with(step_run: step_run).once
      Lifecycle.slot_released(session)
    end
  end
end
