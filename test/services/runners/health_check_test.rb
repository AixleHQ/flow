# frozen_string_literal: true

require "test_helper"

# Runners::HealthCheck (docs/design/agent-runtimes/DESIGN.md §2.5): the runner's
# status from its machines, applied through RunnerStateMachine.
class Runners::HealthCheckTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual)
    @now = Time.current
  end

  test "a runner with no registered machine stays pending" do
    assert_not Runners::HealthCheck.check!(@runner, now: @now)

    assert_equal [ "pending", nil ], @runner.reload.values_at(:status, :status_reason)
  end

  test "once its first machine is heard, a pending runner is connected" do
    create(:runner_environment, runner: @runner, last_heartbeat_at: @now)

    assert Runners::HealthCheck.check!(@runner, now: @now)

    assert_equal [ "connected", nil ], @runner.reload.values_at(:status, :status_reason)
  end

  test "one of two machines stopped degrades the runner after 90 seconds, and it is connected again when the machine is back" do
    create(:runner_environment, runner: @runner, display_name: "build-01", last_heartbeat_at: @now)
    stopped = create(:runner_environment, runner: @runner, display_name: "build-02", last_heartbeat_at: @now)
    Runners::HealthCheck.check!(@runner, now: @now)
    assert_equal "connected", @runner.reload.status

    later = @now + 91.seconds
    RunnerEnvironment.where.not(id: stopped.id).update_all(last_heartbeat_at: later)
    Runners::HealthCheck.check!(@runner, now: later)
    assert_equal [ "degraded", "Offline: build-02." ], @runner.reload.values_at(:status, :status_reason)

    stopped.update!(last_heartbeat_at: later + 10.seconds)
    Runners::HealthCheck.check!(@runner, now: later + 10.seconds)
    assert_equal [ "connected", nil ], @runner.reload.values_at(:status, :status_reason)
  end

  test "every machine silent for more than 3 minutes makes the runner unreachable, and a heard machine brings it back" do
    machine = create(:runner_environment, runner: @runner, display_name: "build-01", last_heartbeat_at: @now)
    Runners::HealthCheck.check!(@runner, now: @now)

    Runners::HealthCheck.check!(@runner, now: @now + 4.minutes)
    assert_equal [ "unreachable", "No machine has been heard for more than 3 minutes: build-01." ],
                 @runner.reload.values_at(:status, :status_reason)

    machine.update!(last_heartbeat_at: @now + 5.minutes)
    Runners::HealthCheck.check!(@runner, now: @now + 5.minutes)
    assert_equal [ "connected", nil ], @runner.reload.values_at(:status, :status_reason)
  end

  test "the reason follows the machines while the status stays" do
    create(:runner_environment, runner: @runner, display_name: "build-01", last_heartbeat_at: @now)
    create(:runner_environment, runner: @runner, display_name: "build-02", last_heartbeat_at: @now - 2.minutes)
    assert Runners::HealthCheck.check!(@runner, now: @now)
    assert_equal [ "degraded", "Offline: build-02." ], @runner.reload.values_at(:status, :status_reason)

    assert_not Runners::HealthCheck.check!(@runner, now: @now), "an unchanged result writes nothing"

    create(:runner_environment, runner: @runner, display_name: "build-03", last_heartbeat_at: @now - 2.minutes)
    assert Runners::HealthCheck.check!(@runner, now: @now)
    assert_equal [ "degraded", "Offline: build-02, build-03." ], @runner.reload.values_at(:status, :status_reason)
  end

  test "an unchanged status leaves updated_at alone" do
    create(:runner_environment, runner: @runner, last_heartbeat_at: @now)
    Runners::HealthCheck.check!(@runner, now: @now)
    before = @runner.reload.updated_at

    Runners::HealthCheck.check!(@runner, now: @now)

    assert_equal before, @runner.reload.updated_at
  end

  test "every machine gone is unreachable with no machine registered" do
    create(:runner_environment, runner: @runner, state: :gone)

    Runners::HealthCheck.check!(@runner, now: @now)

    assert_equal [ "unreachable", "No machine registered." ], @runner.reload.values_at(:status, :status_reason)
  end

  test "a disabled or revoked runner is not changed, even when called directly" do
    create(:runner_environment, runner: @runner, last_heartbeat_at: @now)
    @runner.disable!
    assert_not Runners::HealthCheck.check!(@runner, now: @now)
    assert_equal "disabled", @runner.reload.status

    @runner.revoke!
    assert_not Runners::HealthCheck.check!(@runner, now: @now)
    assert_equal "revoked", @runner.reload.status
  end

  test "a runner disabled after the machines were read is not moved" do
    create(:runner_environment, runner: @runner, last_heartbeat_at: @now)
    stale = Runner.find(@runner.id)
    @runner.disable!

    assert_not Runners::HealthCheck.check!(stale, now: @now)

    assert_equal "disabled", @runner.reload.status
  end

  test "run! checks the live runners only: not disabled, revoked or deleted ones" do
    live = create(:runner_environment, runner: @runner, last_heartbeat_at: Time.current).runner
    disabled = create(:runner, :manual).tap { |runner| create(:runner_environment, runner: runner) }.tap(&:disable!)
    revoked = create(:runner, :manual).tap { |runner| create(:runner_environment, runner: runner) }.tap(&:revoke!)
    deleted = create(:runner, :manual).tap { |runner| create(:runner_environment, runner: runner) }.tap(&:soft_delete!)

    counts = Runners::HealthCheck.run!

    assert_equal({ checked: 1, changed: 1, failed: 0 }, counts)
    assert_equal "connected", live.reload.status
    assert_equal %w[disabled revoked revoked], [ disabled, revoked, deleted ].map { |runner| runner.reload.status }
  end

  test "a runner whose check raises is logged and does not stop the others" do
    broken = create(:runner, :manual)
    create(:runner_environment, runner: @runner, last_heartbeat_at: Time.current)
    real = Runners::ManualAdapter.new
    adapter = Object.new
    adapter.define_singleton_method(:check_health) do |runner, now:|
      raise "boom" if runner.id == broken.id

      real.check_health(runner, now: now)
    end
    Runners::Adapter.stubs(:for).returns(adapter)

    counts = Runners::HealthCheck.run!

    assert_equal({ checked: 2, changed: 1, failed: 1 }, counts)
    assert_equal "connected", @runner.reload.status
  end
end
