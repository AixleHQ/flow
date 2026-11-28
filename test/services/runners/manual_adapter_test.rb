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

  # == the start path (runner-coder.md §7.4): what a manual runner answers to each method ==

  test "it makes no environment, and a registered machine is ready" do
    runner = create(:runner, :manual)
    machine = create(:runner_environment, runner: runner)
    adapter = Runners::ManualAdapter.new

    assert_nil adapter.new_environment(runner)
    assert_equal :ready, adapter.advance!(machine)
  end

  test "cleanup waits for a machine that is not heard" do
    machine = create(:runner_environment, runner: create(:runner, :manual), last_heartbeat_at: nil)

    assert Runners::ManualAdapter.new.cleanup_waits_for_unheard?(machine)
  end

  test "a manual machine cannot be rebuilt: it is revoked and added again" do
    machine = create(:runner_environment, runner: create(:runner, :manual))

    error = assert_raises(Runners::UnsupportedOperation) { Runners::ManualAdapter.new.rebuild!(machine) }

    assert_match(/revoke it and add the host again/, error.message)
    assert_equal "registered", machine.reload.state
  end

  test "launch_refusal is nil while a machine is heard, and names why not otherwise" do
    runner = create(:runner, :manual, name: "Build farm")
    adapter = Runners::ManualAdapter.new

    refusal = adapter.launch_refusal(runner, pick_from: "on the workflow")
    assert_equal [ "runner_unreachable", "Runner \"Build farm\" has no machine registered. Register a machine on it, or pick another runner on the workflow." ],
                 [ refusal.reason, refusal.message ]

    machine = create(:runner_environment, runner: runner, last_heartbeat_at: 5.minutes.ago)
    assert_match(/has no machine online/, adapter.launch_refusal(runner).message)

    machine.update!(last_heartbeat_at: Time.current)
    assert_nil adapter.launch_refusal(runner)
  end

  test "wait_for_environment! refuses a runner with no machine that can take a session, and waits while the machines are busy" do
    runner = create(:runner, :manual, name: "Build farm")
    adapter = Runners::ManualAdapter.new
    carrier = create(:runner_environment, runner: runner, state: "gone")
    session = create(:runner_session, environment: carrier, runner_environment: nil)

    none = assert_raises(Runners::Machines::NoMachine) { adapter.wait_for_environment!(runner, session) }
    assert_match(/has no machine registered/, none.message)

    create(:runner_environment, runner: runner, state: "failed", state_reason: "boom")
    failed = assert_raises(Runners::Machines::NoMachine) { adapter.wait_for_environment!(runner, session) }
    assert_match(/has no machine that can take a session/, failed.message)

    busy = create(:runner_environment, runner: runner)
    create(:runner_session, :holding, environment: busy)
    waits = assert_raises(ContainerRuntime::CapacityError) { adapter.wait_for_environment!(runner, session) }
    assert_equal "runner_capacity", waits.reason
    assert_equal "Waiting for a free machine on runner \"Build farm\" (1 of 1 busy).", waits.message
  end

  test "fail! takes a machine out of rotation with the reason, only while the holder holds it, and leaves a gone machine gone" do
    runner = create(:runner, :manual)
    machine = create(:runner_environment, runner: runner)
    holder = create(:runner_session, :holding, environment: machine)
    adapter = Runners::ManualAdapter.new

    adapter.fail!(machine, "late", holder: create(:runner_session, environment: machine, runner_environment: nil))
    assert_equal [ "registered", holder.id ], [ machine.reload.state, machine.current_session_id ]

    adapter.fail!(machine, "its reset failed", holder: holder)
    assert_equal [ "failed", nil, "its reset failed" ], [ machine.reload.state, machine.current_session_id, machine.state_reason ]

    gone = create(:runner_environment, runner: runner, state: "gone")
    adapter.fail!(gone, "too late")
    assert_equal "gone", gone.reload.state
  end

  test "end_registration! makes the machine gone with the reason it left by, revokes its credentials and signals the relay" do
    machine = create(:runner_environment, runner: create(:runner, :manual))
    Runners::Credentials.issue_pair!(machine)
    Runners::RelaySignals.expects(:machine_revoked).with(machine.id)

    Runners::ManualAdapter.new.end_registration!(machine, ended_by: "revoked")

    assert_equal [ "gone", "revoked" ], [ machine.reload.state, machine.state_reason ]
    assert machine.credentials.all?(&:revoked?)
  end

  # == observe (DESIGN.md §5.1) ==

  test "observe is running while the machine is heard within 90 seconds, and unknown after, never missing" do
    now = Time.current
    adapter = Runners::ManualAdapter.new
    runner = create(:runner, :manual)

    assert_equal :running, adapter.observe(create(:runner_environment, runner: runner, last_heartbeat_at: now - 89.seconds), now: now)
    assert_equal :unknown, adapter.observe(create(:runner_environment, runner: runner, last_heartbeat_at: now - 91.seconds), now: now)
    assert_equal :unknown, adapter.observe(create(:runner_environment, runner: runner, last_heartbeat_at: nil), now: now)
    assert_equal :unknown, adapter.observe(create(:runner_environment, runner: runner, state: :gone, last_heartbeat_at: now - 1.day), now: now)
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
    Runners::Allocator.fail!(failed, "env.reset failed")

    assert_equal [ "degraded", "Failed: build-02 (env.reset failed)." ], check(now)
  end

  test "an offline machine and a failed one are both named" do
    now = Time.current
    create(:runner_environment, runner: runner, display_name: "build-01", last_heartbeat_at: now)
    create(:runner_environment, runner: runner, display_name: "build-02", last_heartbeat_at: now - 2.minutes)
    Runners::Allocator.fail!(create(:runner_environment, runner: runner, display_name: "build-03"), "refresh token reused")

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
    Runners::Allocator.fail!(one, "env.reset failed")
    Runners::Allocator.fail!(two, "refresh token reused")

    assert_equal [ "unreachable",
                   "No machine can take a session: every machine failed: build-01 (env.reset failed); build-02 (refresh token reused)." ],
                 check(Time.current)
  end

  test "a single failed machine is described as such" do
    Runners::Allocator.fail!(create(:runner_environment, runner: runner, display_name: "build-01"), "env.reset failed")

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
    create_list(:runner_environment, 10, runner: runner, display_name: "a-machine-with-a-long-name", last_heartbeat_at: now - 2.minutes)

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
