# frozen_string_literal: true

require "test_helper"

# Runners::Liveness (docs/design/agent-runtimes/DESIGN.md §2.2, §2.5, task 12c):
# a machine's last_heartbeat_at, written at most once per 15 s and carried to
# the runner's last_seen_at, and the display state derived from it.
class Runners::LivenessTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual)
    @machine = create(:runner_environment, runner: @runner, last_heartbeat_at: nil)
  end

  test "the first request is recorded on the machine and on the runner" do
    now = Time.current.change(usec: 0)

    assert Runners::Liveness.record!(runner_id: @runner.id, environment_id: @machine.id, now: now)

    assert_equal now, @machine.reload.last_heartbeat_at
    assert_equal now, @runner.reload.last_seen_at
  end

  test "a machine is written at most once every 15 seconds" do
    now = Time.current.change(usec: 0)
    Runners::Liveness.record!(runner_id: @runner.id, environment_id: @machine.id, now: now)

    assert_not Runners::Liveness.record!(runner_id: @runner.id, environment_id: @machine.id, now: now + 14.seconds)
    assert_equal now, @machine.reload.last_heartbeat_at

    assert Runners::Liveness.record!(runner_id: @runner.id, environment_id: @machine.id, now: now + 15.seconds)
    assert_equal now + 15.seconds, @machine.reload.last_heartbeat_at
    assert_equal now + 15.seconds, @runner.reload.last_seen_at
  end

  test "the runner's last seen is the latest of its machines'" do
    other = create(:runner_environment, runner: @runner, last_heartbeat_at: nil)
    now = Time.current.change(usec: 0)

    Runners::Liveness.record!(runner_id: @runner.id, environment_id: other.id, now: now)
    Runners::Liveness.record!(runner_id: @runner.id, environment_id: @machine.id, now: now - 1.minute)

    assert_equal now, @runner.reload.last_seen_at
  end

  test "recording a heartbeat leaves updated_at alone" do
    before = @machine.updated_at

    Runners::Liveness.record!(runner_id: @runner.id, environment_id: @machine.id)

    assert_equal before, @machine.reload.updated_at
  end

  test "a machine heard within 90 seconds is idle without a session and online with one" do
    now = Time.current
    @machine.update!(last_heartbeat_at: now - 89.seconds)
    assert_equal "idle", state_of(@machine, now)

    @machine.update!(current_session: create(:runner_session, environment: @machine, runner_environment: nil))
    assert_equal "online", state_of(@machine, now)
  end

  test "a machine not heard for 90 seconds, or never, is offline" do
    now = Time.current
    @machine.update!(last_heartbeat_at: now - 91.seconds)
    assert_equal "offline", state_of(@machine, now)

    @machine.update!(last_heartbeat_at: nil)
    assert_equal "offline", state_of(@machine, now)
  end

  test "a silent machine executing a delivered op within its deadline is not offline" do
    now = Time.current
    @machine.update!(last_heartbeat_at: now - 5.minutes)
    operation = enqueue_for(@machine, deadline_at: now + 10.minutes)

    assert_equal "offline", state_of(@machine, now), "an op that was not delivered does not count"

    operation.update!(state: :delivered, delivered_at: now - 4.minutes)
    assert_equal "online", state_of(@machine, now)

    assert_equal "offline", state_of(@machine, now + 11.minutes), "past the op's deadline it is offline again"
  end

  test "failed and gone machines show as such, however recently they were heard" do
    gone = create(:runner_environment, runner: @runner, state: :gone)
    Runners::Machines.fail!(@machine, "env.reset failed")

    states = Runners::Liveness.states([ @machine.reload, gone ])

    assert_equal({ @machine.id => "failed", gone.id => "gone" }, states)
  end

  private

  def state_of(machine, now)
    Runners::Liveness.states([ machine.reload ], now: now).fetch(machine.id)
  end

  def enqueue_for(machine, deadline_at:)
    session = create(:runner_session, :holding, environment: machine)
    Runners::Operations.enqueue!(machine.reload, op: "exec", payload: { "cmd" => "true" }, session: session,
                                                 deadline_at: deadline_at)
  end
end
