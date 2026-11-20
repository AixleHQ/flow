# frozen_string_literal: true

require "test_helper"

# Runners::RelaySignals (docs/design/agent-runtimes/runner-relay.md §8.1): the three
# messages the platform publishes on `runner_relay` for the relay service, each at
# each of its triggers, after the commit and never on a rollback.
class Runners::RelaySignalsTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual)
    @machine = create(:runner_environment, runner: @runner)
    @pubsub = ActionCable.server.pubsub
    @pubsub.clear_messages(Runners::RelaySignals::CHANNEL)
  end

  # -- machine_session -------------------------------------------------------

  test "a session taking a machine sends machine_session with its route token and ports" do
    session = runner_session

    Runners::Machines.acquire!(session)

    assert_equal [ machine_session(@machine, session) ], signals
    assert_equal Runners::Tunnel.ports(session).keys, signals.sole["ports"].keys
  end

  test "a session that keeps the machine it holds sends nothing again" do
    session = runner_session
    Runners::Machines.acquire!(session)
    clear

    Runners::Machines.acquire!(session)

    assert_empty signals
  end

  test "the machine's ports are the session's, host ports with network: host" do
    @runner.update!(config: { "container" => { "network" => "host" } })
    session = runner_session

    Runners::Machines.acquire!(session)

    assert_equal Runners::Tunnel.ports(session.reload), signals.sole["ports"]
    assert_not_equal 7681, signals.sole["ports"]["tty"]
  end

  test "a session leaving the machine on release sends machine_session without a session" do
    session = held_session

    Runners::Machines.release!(@machine, session)

    assert_equal [ machine_session(@machine, nil) ], signals
  end

  test "a machine failed while it holds a session sends machine_session without a session" do
    session = held_session

    Runners::Machines.fail!(@machine, "reset failed", holder: session)

    assert_equal [ machine_session(@machine, nil) ], signals
  end

  test "a runner's revoke sends machine_session without a session for a machine that held one" do
    held_session

    @runner.revoke!

    assert_includes signals, machine_session(@machine, nil)
  end

  test "the loss of contact with a revoked runner's machine sends machine_session without a session" do
    session = held_session

    Runners::ContactLoss.send(:release_machine, session)

    assert_equal [ machine_session(@machine, nil) ], signals
    assert_nil @machine.reload.current_session_id
  end

  test "a write that changes nothing about the hold sends nothing" do
    held_session

    @machine.update!(display_name: "renamed")

    assert_empty signals
  end

  # -- session_ended ---------------------------------------------------------

  test "a runner session leaving ready sends session_ended, by whichever event it leaves" do
    %i[start_finishing! fail! cancel!].each do |event|
      session = create(:runner_session, environment: @machine, state: "ready")
      clear

      session.public_send(event)

      assert_equal [ { "type" => "session_ended", "session_id" => session.id } ], signals, event.to_s
    end
  end

  test "a state written directly out of ready sends session_ended too" do
    session = create(:runner_session, environment: @machine, state: "ready")
    clear

    session.update!(state: "finished", finished_at: Time.current)

    assert_equal [ { "type" => "session_ended", "session_id" => session.id } ], signals
  end

  test "a runner session that was not ready sends no session_ended" do
    session = create(:runner_session, environment: @machine, state: "running")
    clear

    session.fail!

    assert_empty signals
  end

  test "a hosted session leaving ready sends no session_ended" do
    session = create(:terminal_session, state: "ready")
    clear

    session.fail!

    assert_empty signals
  end

  # -- machine_revoked -------------------------------------------------------

  test "an unregistered machine sends machine_revoked" do
    Runners::Registration.unregister!(@machine)

    assert_includes signals, { "type" => "machine_revoked", "environment_id" => @machine.id }
  end

  test "a Revoke of a machine sends machine_revoked" do
    assert Runners::Registration.revoke!(@machine)

    assert_equal [ { "type" => "machine_revoked", "environment_id" => @machine.id } ], signals
  end

  test "a runner's revoke sends machine_revoked for each of its machines" do
    other = create(:runner_environment, runner: @runner)

    @runner.revoke!

    revoked = signals.select { |signal| signal["type"] == "machine_revoked" }
    assert_equal [ @machine.id, other.id ].sort, revoked.map { |signal| signal["environment_id"] }.sort
  end

  # -- timing and failure ----------------------------------------------------

  test "a signal waits for the transaction to commit" do
    session = runner_session

    ActiveRecord::Base.transaction do
      Runners::Machines.acquire!(session)
      assert_empty signals, "nothing is published before the commit"
    end

    assert_equal [ machine_session(@machine, session) ], signals
  end

  test "a rolled-back transaction sends nothing" do
    session = runner_session

    ActiveRecord::Base.transaction do
      Runners::Machines.acquire!(session)
      raise ActiveRecord::Rollback
    end

    assert_empty signals
    assert_nil @machine.reload.current_session_id
  end

  test "a failed publish is logged and swallowed" do
    session = runner_session
    @pubsub.stubs(:broadcast).raises(StandardError, "redis is down")
    Rails.logger.stubs(:warn)
    Rails.logger.expects(:warn).with(regexp_matches(/RelaySignals\] machine_session signal failed: StandardError: redis is down/)).once

    assert_equal @machine, Runners::Machines.acquire!(session)
    assert_equal session.id, @machine.reload.current_session_id
  end

  private

  def runner_session
    create(:runner_session, environment: @machine, runner_environment: nil)
  end

  def held_session
    session = runner_session
    Runners::Machines.acquire!(session)
    clear
    session
  end

  def machine_session(machine, session)
    { "type" => "machine_session", "environment_id" => machine.id, "session_id" => session&.id,
      "route_token" => session&.route_token, "ports" => (Runners::Tunnel.ports(session) if session) }
  end

  def signals
    @pubsub.broadcasts(Runners::RelaySignals::CHANNEL).map { |message| JSON.parse(message) }
  end

  def clear
    @pubsub.clear_messages(Runners::RelaySignals::CHANNEL)
  end
end
