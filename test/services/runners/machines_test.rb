# frozen_string_literal: true

require "test_helper"

# Runners::Machines (task 8a, decision 2): a session takes a free registered
# machine of its runner, one session per machine, until Runners::Allocator.
class Runners::MachinesTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual, name: "Build farm")
    @machine = create(:runner_environment, runner: @runner)
  end

  test "a session takes a free machine, and both sides record it, without touching the caller's session" do
    session = runner_session
    session.initial_prompt = "changed by the caller"

    assert_equal @machine, Runners::Machines.acquire!(session)
    assert_nil session.runner_environment_id, "the caller's object is not changed"
    assert_equal [ "initial_prompt" ], session.changed, "nor saved"
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

  test "a runner whose every machine failed fails the launch at once, naming the machines and pointing to Return to service" do
    @machine.update!(display_name: "build-01")
    Runners::Machines.fail!(@machine, "env.reset failed after session 7: reset_failed: volume in use")

    error = assert_raises(Runners::Machines::NoMachine) { Runners::Machines.acquire!(runner_session) }

    assert_equal "runner_unreachable", error.reason
    assert_equal "Runner \"Build farm\" has no machine that can take a session: its machine is out of rotation: " \
                 "build-01 (env.reset failed after session 7: reset_failed: volume in use). " \
                 "Fix the machine and press Return to service on the runner page, or pick another runner.", error.message
  end

  test "a failed session adds to the machine's streak, and a session that ends well sets it back to 0" do
    first = runner_session
    Runners::Machines.acquire!(first)
    Runners::Machines.release!(@machine, first, failed: true)
    assert_equal 1, @machine.reload.consecutive_failures

    second = runner_session
    Runners::Machines.acquire!(second)
    Runners::Machines.release!(@machine, second, failed: true)
    assert_equal [ "registered", 2 ], [ @machine.reload.state, @machine.consecutive_failures ]

    third = runner_session
    Runners::Machines.acquire!(third)
    Runners::Machines.release!(@machine, third)
    assert_equal 0, @machine.reload.consecutive_failures
  end

  test "the third failed session in a row takes the machine out of rotation, with the reason" do
    @machine.update!(display_name: "build-01")
    3.times do
      session = runner_session
      Runners::Machines.acquire!(session) if @machine.reload.state == "registered"
      Runners::Machines.release!(@machine, session, failed: true)
    end

    @machine.reload
    assert_equal [ "failed", nil, 3 ], [ @machine.state, @machine.current_session_id, @machine.consecutive_failures ]
    assert_equal "build-01 failed 3 sessions in a row", @machine.state_reason
  end

  test "Return to service resets a failed machine with no session, and an op that succeeds frees it" do
    @machine.update!(consecutive_failures: 3)
    Runners::Machines.fail!(@machine, "build-01 failed 3 sessions in a row")
    host = ContainerRuntime::FakeHostRunner.new(@machine)

    assert Runners::Machines.return_to_service!(@machine)

    @machine.reload
    assert_equal [ %w[env.reset], [ nil ] ], [ host.ops, host.operations.pluck(:session_id) ]
    assert_equal [ "registered", nil, nil, 0 ], [ @machine.state, @machine.state_reason, @machine.current_session_id, @machine.consecutive_failures ]
    assert_equal @machine, Runners::Machines.acquire!(runner_session)
  ensure
    host&.stop
  end

  test "a machine that is resetting takes no session, and a second press sends nothing" do
    Runners::Machines.fail!(@machine, "boom")
    host = ContainerRuntime::FakeHostRunner.new(@machine)
    host.answer_with("env.reset", :none)

    assert Runners::Machines.return_to_service!(@machine)
    assert_not Runners::Machines.return_to_service!(@machine), "it is not failed any more"

    assert_equal "resetting", @machine.reload.state
    assert_equal %w[env.reset], host.ops
    error = assert_raises(Runners::Machines::NoMachine) { Runners::Machines.acquire!(runner_session) }
    assert_match(/its machine is out of rotation: #{@machine.display_name} \(being returned to service\)/, error.message)
  ensure
    host&.stop
  end

  test "a Return to service whose reset fails leaves the machine failed with the new reason" do
    @machine.update!(display_name: "build-01")
    Runners::Machines.fail!(@machine, "old reason")
    host = ContainerRuntime::FakeHostRunner.new(@machine)
    host.answer_with("env.reset", "status" => "error", "error" => { "class" => "reset_failed", "message" => "volume in use" })

    Runners::Machines.return_to_service!(@machine)

    @machine.reload
    assert_equal "failed", @machine.state
    assert_equal "build-01 failed to reset on Return to service: reset_failed: volume in use", @machine.state_reason
  ensure
    host&.stop
  end

  test "a Return to service that nobody answers fails the machine when the op expires" do
    Runners::Machines.fail!(@machine, "old reason")
    Runners::Machines.return_to_service!(@machine)
    assert_equal "resetting", @machine.reload.state

    travel_to 20.minutes.from_now do
      assert_equal 1, Runners::Operations.expire_overdue!
    end

    @machine.reload
    assert_equal "failed", @machine.state
    assert_match(/failed to reset on Return to service: the runner did not answer/, @machine.state_reason)
  end

  test "a capacity wait counts only the machines that can come back" do
    failed = create(:runner_environment, runner: @runner)
    Runners::Machines.fail!(failed, "env.reset failed after session 7: the runner did not answer")
    Runners::Machines.acquire!(runner_session)

    error = assert_raises(ContainerRuntime::CapacityError) { Runners::Machines.acquire!(runner_session) }

    assert_equal "Waiting for a free machine on runner \"Build farm\" (1 of 1 busy).", error.message
  end

  test "a late failure of a session that released the machine leaves the next session's hold alone" do
    first = runner_session
    observed = Runners::Machines.acquire!(first)
    Runners::Machines.release!(observed, first)
    second = runner_session
    Runners::Machines.acquire!(second)

    Runners::Machines.fail!(observed, "env.reset failed after session #{first.id}: the runner did not answer", holder: first)

    @machine.reload
    assert_equal [ "registered", second.id, nil ], [ @machine.state, @machine.current_session_id, @machine.state_reason ]
    Runners::Machines.fail!(observed, "refresh token reused")
    assert_equal [ "failed", nil ], [ @machine.reload.state, @machine.current_session_id ],
                 "without a holder, the machine fails whoever holds it"
  end

  test "availability is a result: available, none registered, or every machine failed" do
    assert_equal :available, Runners::Machines.availability(@runner).status
    Runners::Machines.acquire!(runner_session)
    assert Runners::Machines.availability(@runner).available?, "a busy machine can come back"

    Runners::Machines.fail!(@machine, "env.reset failed after session 7: reset_failed: volume in use")
    failed = Runners::Machines.availability(@runner)
    assert_equal [ :all_failed, [ @machine ] ], [ failed.status, failed.failed ]

    @machine.update!(state: :gone)
    assert_equal :none_registered, Runners::Machines.availability(@runner).status
  end

  test "an offline machine is skipped while another is free" do
    @machine.update!(last_heartbeat_at: 2.minutes.ago)
    online = create(:runner_environment, runner: @runner)

    assert_equal online, Runners::Machines.acquire!(runner_session)
  end

  test "every machine offline refuses the launch with a message that names the runner" do
    @machine.update!(last_heartbeat_at: 2.minutes.ago)

    error = assert_raises(Runners::Machines::NoMachine) { Runners::Machines.acquire!(runner_session) }

    assert_equal "runner_unreachable", error.reason
    assert_match(/\ARunner "Build farm" has no machine online: its machine is offline \(#{@machine.display_name}\)/, error.message)
    assert_nil @machine.reload.current_session_id
  end

  test "an offline machine does not count as busy: the only reachable one busy is a capacity wait" do
    create(:runner_environment, runner: @runner, last_heartbeat_at: 2.minutes.ago)
    Runners::Machines.acquire!(runner_session)

    error = assert_raises(ContainerRuntime::CapacityError) { Runners::Machines.acquire!(runner_session) }

    assert_equal "Waiting for a free machine on runner \"Build farm\" (1 of 1 busy).", error.message
  end

  test "a busy machine that keeps sending heartbeats while it runs an op stays online, and a silent one is offline whatever op it holds" do
    holder = runner_session
    Runners::Machines.acquire!(holder)
    operation = Runners::Operations.enqueue!(@machine.reload, op: "exec", payload: { "cmd" => "true" }, session: holder,
                                                              deadline_at: 5.minutes.from_now)
    operation.update!(state: :delivered, delivered_at: Time.current)

    @machine.update!(last_heartbeat_at: 30.seconds.ago)
    assert Runners::Machines.availability(@runner).available?

    @machine.update!(last_heartbeat_at: 5.minutes.ago)
    assert_equal :all_offline, Runners::Machines.availability(@runner).status, "a delivered op within its deadline no longer counts as heard"
  end

  test "the wait for a free machine carries the runner_capacity reason, not the cluster's" do
    Runners::Machines.acquire!(runner_session)

    error = assert_raises(ContainerRuntime::CapacityError) { Runners::Machines.acquire!(runner_session) }

    assert_equal "runner_capacity", error.reason
  end

  test "availability reports every machine offline, and failed machines only when none is registered" do
    @machine.update!(last_heartbeat_at: 2.minutes.ago)
    offline = Runners::Machines.availability(@runner)
    assert_equal [ :all_offline, [ @machine ] ], [ offline.status, offline.offline ]

    Runners::Machines.fail!(@machine, "env.reset failed")
    assert_equal :all_failed, Runners::Machines.availability(@runner).status
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
