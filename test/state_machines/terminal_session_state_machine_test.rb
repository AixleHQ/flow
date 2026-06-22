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
end
