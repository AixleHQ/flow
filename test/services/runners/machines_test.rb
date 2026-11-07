# frozen_string_literal: true

require "test_helper"

# Runners::Machines (task 8a, decision 2): a session takes a free registered
# machine of its runner, one session per machine, until Runners::Allocator.
class Runners::MachinesTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual, name: "Build farm")
    @machine = create(:runner_environment, runner: @runner)
  end

  test "a session takes a free machine, and both sides record it" do
    session = runner_session

    assert_equal @machine, Runners::Machines.acquire!(session)
    assert_equal @machine.id, session.runner_environment_id
    assert_equal @machine.id, session.reload.runner_environment_id
    assert_equal session.id, @machine.reload.current_session_id
    assert_equal @machine, Runners::Machines.acquire!(session), "the session keeps the machine it holds"
  end

  test "no machine registered fails with a message that names the runner" do
    @machine.update!(state: :gone)

    error = assert_raises(Runners::Machines::NoMachine) { Runners::Machines.acquire!(runner_session) }

    assert_equal "runner_unreachable", error.reason
    assert_equal "Runner \"Build farm\" has no machine registered. Register a machine on it, or pick another runner.",
                 error.message
  end

  test "every machine busy is a capacity wait" do
    Runners::Machines.acquire!(runner_session)

    error = assert_raises(ContainerRuntime::CapacityError) { Runners::Machines.acquire!(runner_session) }

    assert_equal "Waiting for a free machine on runner \"Build farm\" (1 of 1 busy).", error.message
  end

  test "a machine is free again after its reset" do
    first = runner_session
    Runners::Machines.acquire!(first)
    Runners::Machines.release!(@machine, first)

    assert_nil @machine.reload.current_session_id
    assert_equal @machine, Runners::Machines.acquire!(runner_session)
  end

  test "a failed machine is held by no session and takes none, whatever happens to the session" do
    first = runner_session
    Runners::Machines.acquire!(first)
    Runners::Machines.fail!(@machine, "env.reset failed after session #{first.id}: reset_failed: volume in use")

    @machine.reload
    assert_equal "failed", @machine.state
    assert_nil @machine.current_session_id
    Runners::Machines.release!(@machine, first)
    first.destroy!
    assert_equal "failed", @machine.reload.state, "neither a late release nor the session's deletion frees it"
    assert_raises(Runners::Machines::NoMachine) { Runners::Machines.acquire!(runner_session) }
  end

  test "a runner whose every machine failed fails the launch at once, naming the machines and how to bring one back" do
    @machine.update!(display_name: "build-01")
    Runners::Machines.fail!(@machine, "env.reset failed after session 7: reset_failed: volume in use")

    error = assert_raises(Runners::Machines::NoMachine) { Runners::Machines.acquire!(runner_session) }

    assert_equal "runner_unreachable", error.reason
    assert_equal "Runner \"Build farm\" has no machine that can take a session: its machine failed: " \
                 "build-01 (env.reset failed after session 7: reset_failed: volume in use). " \
                 "To bring a machine back, run `aixle-runner unregister` on it, then `aixle-runner configure` again, " \
                 "or pick another runner.", error.message
  end

  test "a capacity wait counts only the machines that can come back" do
    failed = create(:runner_environment, runner: @runner)
    Runners::Machines.fail!(failed, "env.reset failed after session 7: the runner did not answer")
    Runners::Machines.acquire!(runner_session)

    error = assert_raises(ContainerRuntime::CapacityError) { Runners::Machines.acquire!(runner_session) }

    assert_equal "Waiting for a free machine on runner \"Build farm\" (1 of 1 busy).", error.message
  end

  test "a gone machine stays gone when it fails" do
    @machine.update!(state: :gone)

    Runners::Machines.fail!(@machine, "held by stale session 1")

    assert_equal "gone", @machine.reload.state
  end

  test "a machine of another runner is never taken" do
    create(:runner_environment)

    Runners::Machines.acquire!(runner_session)

    assert_raises(ContainerRuntime::CapacityError) { Runners::Machines.acquire!(runner_session) }
  end

  private

  def runner_session
    create(:runner_session, environment: @machine, runner_environment: nil)
  end
end
