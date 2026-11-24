# frozen_string_literal: true

require "test_helper"

class TerminalSessionStateMachineTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
  end

  # == states ==

  test "initial state is not_started" do
    session = create(:terminal_session, user: @user)
    assert_equal "not_started", session.state
  end

  test "finishing is a recognized state" do
    assert_includes TerminalSession.aasm.states.map(&:name), :finishing
  end

  # == start_finishing event ==

  test "start_finishing transitions from running to finishing" do
    session = create(:terminal_session, :running, user: @user)
    session.start_finishing!
    assert_equal "finishing", session.state
    assert_not_nil session.finishing_at
  end

  test "start_finishing transitions from ready to finishing" do
    session = create(:terminal_session, user: @user, state: "ready")
    session.start_finishing!
    assert_equal "finishing", session.state
  end

  test "start_finishing transitions from not_started to finishing" do
    session = create(:terminal_session, user: @user)
    session.start_finishing!
    assert_equal "finishing", session.state
  end

  test "start_finishing is not allowed from finishing" do
    session = create(:terminal_session, :finishing, user: @user)
    assert_not session.may_start_finishing?
  end

  test "start_finishing is not allowed from finished" do
    session = create(:terminal_session, user: @user, state: "finished")
    assert_not session.may_start_finishing?
  end

  test "start_finishing is not allowed from failed" do
    session = create(:terminal_session, user: @user, state: "failed")
    assert_not session.may_start_finishing?
  end

  # == finish event (only from finishing) ==

  test "finish transitions only from finishing to finished" do
    session = create(:terminal_session, :finishing, user: @user)
    session.finish!
    assert_equal "finished", session.state
    assert_not_nil session.finished_at
  end

  test "finish is not allowed directly from running" do
    session = create(:terminal_session, :running, user: @user)
    assert_not session.may_finish?
  end

  test "finish is not allowed directly from ready" do
    session = create(:terminal_session, user: @user, state: "ready")
    assert_not session.may_finish?
  end

  test "finish is not allowed directly from not_started" do
    session = create(:terminal_session, user: @user)
    assert_not session.may_finish?
  end

  # == fail event ==

  test "fail transitions from finishing to failed" do
    session = create(:terminal_session, :finishing, user: @user)
    session.fail!
    assert_equal "failed", session.state
  end

  test "fail transitions from running to failed" do
    session = create(:terminal_session, :running, user: @user)
    session.fail!
    assert_equal "failed", session.state
  end

  # == finishing? helper ==

  test "finishing? returns true only when in finishing state" do
    finishing_session = create(:terminal_session, :finishing, user: @user)
    running_session = create(:terminal_session, :running, user: @user)

    assert finishing_session.finishing?
    assert_not running_session.finishing?
  end

  # == active? excludes finishing ==

  test "active? returns false when state is finishing" do
    session = create(:terminal_session, :finishing, user: @user)
    assert_not session.active?
  end

  # == scopes ==

  test "active scope does not include finishing sessions" do
    create(:terminal_session, :running, user: @user)
    create(:terminal_session, :finishing, user: @user)

    assert_equal 1, TerminalSession.active.count
  end

  test "finishing scope returns finishing sessions" do
    create(:terminal_session, :running, user: @user)
    finishing = create(:terminal_session, :finishing, user: @user)

    finishing_ids = TerminalSession.finishing.pluck(:id)
    assert_equal [ finishing.id ], finishing_ids
  end

  test "completed scope still returns only finished sessions" do
    create(:terminal_session, :finishing, user: @user)
    finished = create(:terminal_session, user: @user, state: "finished")

    completed_ids = TerminalSession.completed.pluck(:id)
    assert_equal [ finished.id ], completed_ids
  end

  # == on_finishing callback records timestamp ==

  test "on_finishing callback sets finishing_at" do
    session = create(:terminal_session, :running, user: @user)
    assert_nil session.finishing_at

    session.start_finishing!
    session.reload

    assert_not_nil session.finishing_at
  end

  # == events Sessions::Lifecycle.finalize and the suspension moves use ==

  test "finish_without_request ends a session that was never asked to finish" do
    %w[not_started queued running ready].each do |from|
      session = create(:terminal_session, user: @user, state: from, container_id: "ctr-1")
      assert session.may_finish_without_request?, "from #{from}"

      session.finish_without_request!

      assert_equal "finished", session.reload.state
      assert_not_nil session.finished_at
      assert_nil session.container_id
    end
  end

  test "finish_without_request is refused once a session is finishing or over" do
    %w[finishing finished failed cancelled suspended].each do |from|
      assert_not create(:terminal_session, user: @user, state: from).may_finish_without_request?, "from #{from}"
    end
  end

  test "finish_without_request keeps the time the session ended when it is already set" do
    ended = 2.hours.ago.change(usec: 0)
    session = create(:terminal_session, user: @user, state: "ready", finished_at: ended)

    session.finish_without_request!

    assert_equal ended, session.reload.finished_at
  end

  test "fail_after_finish moves only a finished session to failed" do
    session = create(:terminal_session, user: @user, state: "finished", container_id: "ctr-1")

    session.fail_after_finish!

    assert_equal "failed", session.reload.state
    assert_nil session.container_id
    %w[not_started queued running ready finishing failed cancelled suspended].each do |from|
      assert_not create(:terminal_session, user: @user, state: from).may_fail_after_finish?, "from #{from}"
    end
  end

  test "mark_suspended takes a session that ran, and clears its container" do
    %w[running ready finishing].each do |from|
      session = create(:terminal_session, user: @user, state: from, container_id: "ctr-1")

      session.mark_suspended!

      assert_equal "suspended", session.reload.state
      assert_nil session.container_id
      assert_not_nil session.finished_at
    end
    %w[not_started queued finished failed cancelled suspended].each do |from|
      assert_not create(:terminal_session, user: @user, state: from).may_mark_suspended?, "from #{from}"
    end
  end

  test "expire_suspended_step moves only a suspended session to failed" do
    session = create(:terminal_session, user: @user, state: "suspended")

    session.expire_suspended_step!

    assert_equal "failed", session.reload.state
    %w[not_started queued running ready finishing finished failed cancelled restored].each do |from|
      assert_not create(:terminal_session, user: @user, state: from).may_expire_suspended_step?, "from #{from}"
    end
  end

  # The reason the moves above are events of their own: failing or finishing a
  # suspended session through the usual events has to stay refused.
  test "a suspended session can be neither failed nor finished through the usual events" do
    session = create(:terminal_session, user: @user, state: "suspended")

    assert_not session.may_fail?
    assert_not session.may_finish?
    assert_not session.may_cancel?
  end

  # == ending rules ==

  test "ending_error drops the queue's own error after a requested finish, and keeps a real one" do
    generic = TerminalSession::GENERIC_ERROR_MESSAGES.first
    finishing = build(:terminal_session, user: @user, finishing_at: Time.current)
    plain = build(:terminal_session, user: @user)

    assert_nil finishing.ending_error(generic)
    assert_equal "Agent image could not be pulled", finishing.ending_error("Agent image could not be pulled")
    assert_equal generic, plain.ending_error(generic)
    assert_nil plain.ending_error(nil)
  end

  test "ending_state: a stop before the session was usable is a cancellation, anything else finishes" do
    assert_equal "cancelled", build(:terminal_session, user: @user, state: "cancelled").ending_state(nil)
    assert_equal "failed", build(:terminal_session, user: @user, state: "running").ending_state("boom")
    assert_equal "failed", build(:terminal_session, user: @user, state: "failed").ending_state(nil)
    assert_equal "cancelled", build(:terminal_session, user: @user, finishing_at: Time.current).ending_state(nil)
    assert_equal "finished", build(:terminal_session, user: @user, finishing_at: Time.current,
                                                      ready_at: 1.minute.ago).ending_state(nil)
    assert_equal "finished", build(:terminal_session, user: @user).ending_state(nil)
  end
end
