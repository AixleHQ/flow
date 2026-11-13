# frozen_string_literal: true

require "test_helper"

class Runners::ManualAdapterTest < ActiveSupport::TestCase
  test "the registry hands out the manual adapter, and refuses the types that have none yet" do
    assert_instance_of Runners::ManualAdapter, Runners::Adapter.for(build(:runner, :manual))
    assert_equal %w[manual], Runners::Adapter.available_types

    %w[coder kubernetes].each do |type|
      error = assert_raises(Runners::Adapter::UnavailableType) { Runners::Adapter.for_type(type) }
      assert_match(/not available yet/, error.message)
    end
  end

  test "a manual runner can neither be provisioned nor rebuilt" do
    capabilities = Runners::ManualAdapter.new.capabilities(build(:runner, :manual))

    assert_equal({ provisionable: false, rebuildable: false }, capabilities.to_h)
  end

  # == check_health (DESIGN.md §2.5) ==

  test "a runner whose first machine has not registered is pending, with no reason" do
    health = Runners::ManualAdapter.new.check_health(create(:runner, :manual))

    assert_equal [ "pending", nil ], [ health.status, health.reason ]
  end

  test "every registered machine heard within 90 seconds is connected" do
    now = Time.current
    create(:runner_environment, runner: runner, last_heartbeat_at: now - 89.seconds)
    create(:runner_environment, runner: runner, last_heartbeat_at: now)

    assert_equal [ "connected", nil ], check(now)
  end

  test "a machine that is not heard for 90 seconds makes the runner degraded, and the reason names it" do
    now = Time.current
    create(:runner_environment, runner: runner, display_name: "build-01", last_heartbeat_at: now)
    create(:runner_environment, runner: runner, display_name: "build-02", last_heartbeat_at: now - 91.seconds)

    assert_equal [ "degraded", "Offline: build-02." ], check(now)
  end

  test "a machine that failed makes the runner degraded, and the reason names it and why" do
    now = Time.current
    create(:runner_environment, runner: runner, display_name: "build-01", last_heartbeat_at: now)
    failed = create(:runner_environment, runner: runner, display_name: "build-02", last_heartbeat_at: now)
    Runners::Machines.fail!(failed, "env.reset failed")

    assert_equal [ "degraded", "Failed: build-02 (env.reset failed)." ], check(now)
  end

  test "an offline machine and a failed one are both named" do
    now = Time.current
    create(:runner_environment, runner: runner, display_name: "build-01", last_heartbeat_at: now)
    create(:runner_environment, runner: runner, display_name: "build-02", last_heartbeat_at: now - 2.minutes)
    Runners::Machines.fail!(create(:runner_environment, runner: runner, display_name: "build-03"), "refresh token reused")

    assert_equal [ "degraded", "Offline: build-02. Failed: build-03 (refresh token reused)." ], check(now)
  end

  test "every machine silent for 90 seconds but not for 3 minutes is still degraded" do
    now = Time.current
    create(:runner_environment, runner: runner, display_name: "build-01", last_heartbeat_at: now - 179.seconds)

    assert_equal [ "degraded", "Offline: build-01." ], check(now)
  end

  test "no registered machine heard for more than 3 minutes is unreachable" do
    now = Time.current
    create(:runner_environment, runner: runner, display_name: "build-01", last_heartbeat_at: now - 181.seconds)
    create(:runner_environment, runner: runner, display_name: "build-02", last_heartbeat_at: nil)

    assert_equal [ "unreachable", "No machine has been heard for more than 3 minutes: build-01, build-02." ], check(now)
  end

  test "a machine that was never heard counts as silent" do
    create(:runner_environment, runner: runner, display_name: "build-01", last_heartbeat_at: nil)

    assert_equal "unreachable", check(Time.current).first
  end

  test "every machine failed is unreachable, with the failures as the reason" do
    one = create(:runner_environment, runner: runner, display_name: "build-01")
    two = create(:runner_environment, runner: runner, display_name: "build-02")
    Runners::Machines.fail!(one, "env.reset failed")
    Runners::Machines.fail!(two, "refresh token reused")

    assert_equal [ "unreachable",
                   "No machine can take a session: every machine failed: build-01 (env.reset failed); build-02 (refresh token reused)." ],
                 check(Time.current)
  end

  test "a single failed machine is described as such" do
    Runners::Machines.fail!(create(:runner_environment, runner: runner, display_name: "build-01"), "env.reset failed")

    assert_equal "No machine can take a session: its machine failed: build-01 (env.reset failed).", check(Time.current).last
  end

  test "every machine gone is unreachable with no machine registered" do
    create(:runner_environment, runner: runner, state: :gone)

    assert_equal [ "unreachable", "No machine registered." ], check(Time.current)
  end

  test "a gone machine does not count against the others" do
    now = Time.current
    create(:runner_environment, runner: runner, state: :gone, last_heartbeat_at: now - 1.day)
    create(:runner_environment, runner: runner, last_heartbeat_at: now)

    assert_equal [ "connected", nil ], check(now)
  end

  test "the machines of another runner are not read" do
    now = Time.current
    create(:runner_environment, last_heartbeat_at: now)
    create(:runner_environment, runner: runner, last_heartbeat_at: now - 1.hour)

    assert_equal "unreachable", check(now).first
  end

  test "the reason is cut to 255 characters" do
    now = Time.current
    create(:runner_environment, runner: runner, last_heartbeat_at: now)
    create_list(:runner_environment, 30, runner: runner, last_heartbeat_at: now - 2.minutes)

    assert_operator check(now).last.length, :<=, 255
  end

  test "the check makes no outbound call" do
    now = Time.current
    create(:runner_environment, runner: runner, last_heartbeat_at: now)

    assert_equal "connected", check(now).first
  end

  private

  def runner = @runner ||= create(:runner, :manual)

  def check(now)
    health = Runners::ManualAdapter.new.check_health(runner, now: now)
    [ health.status, health.reason ]
  end
end
