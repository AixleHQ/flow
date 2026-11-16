# frozen_string_literal: true

require "test_helper"

# Runners::Liveness (docs/design/agent-runtimes/DESIGN.md §2.2, §2.5, task 12c):
# a machine's last_heartbeat_at, written at most once per 15 s and carried to
# the runner's last_seen_at.
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
end
