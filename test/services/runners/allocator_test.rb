# frozen_string_literal: true

require "test_helper"

# Runners::Allocator (docs/design/agent-runtimes/runner-coder.md §5) on a
# provisionable runner, with a fake adapter registered for the test only. The
# `manual` side of the same contract is Runners::MachinesTest and
# Runners::ManualAdapterTest.
class Runners::AllocatorTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :coder, name: "Cloud farm", max_concurrency: 3, max_environments: 2)
    @adapter = with_fake_provisioned_adapter
    # A session needs an environment to be built from; this one is out of the picture.
    @carrier = create(:runner_environment, :allocated, runner: @runner, state: "gone")
  end

  def runner_session
    create(:runner_session, environment: @carrier, runner_environment: nil)
  end

  def environments = RunnerEnvironment.where(runner: @runner).where.not(id: @carrier.id)

  # == the fake is an adapter ==

  test "the fake adapter answers every method the allocator calls on a type, as the real ones do" do
    methods = Runners::Adapter.public_instance_methods(false) - [ :type, :config_schema, :wait_for_environment! ]

    assert_empty methods - FakeProvisionedAdapter.public_instance_methods(false)
    assert_equal "connected", @adapter.check_health(@runner).status
    assert @adapter.capabilities(@runner).provisionable
  end

  # == step 2: a new environment ==

  test "a session that finds no environment gets one made for it, held, and waits while it is built" do
    session = runner_session

    error = assert_raises(Runners::Allocator::Pending) { Runners::Allocator.acquire!(session) }

    assert_equal "runner_provisioning", error.reason
    assert_kind_of ContainerRuntime::CapacityError, error
    environment = environments.sole
    assert_equal "provisioning", environment.state
    assert_equal "allocated", environment.origin
    assert_equal session.id, environment.current_session_id
    assert_equal environment.id, session.reload.runner_environment_id
    assert_equal @runner.company_id, environment.company_id
    assert environment.external_id.present?
    assert environment.boot_started_at.present?, "the clock starts with the first external id"
  end

  test "a retried acquire gets the same environment, advances it, and answers once it is idle" do
    session = runner_session
    assert_raises(Runners::Allocator::Pending) { Runners::Allocator.acquire!(session) }

    assert_raises(Runners::Allocator::Pending) { Runners::Allocator.acquire!(session) }
    environment = environments.sole
    assert_equal "booting", environment.reload.state, "prepare said ready, the install ran, the row moved on"

    assert_raises(Runners::Allocator::Pending) { Runners::Allocator.acquire!(session) }
    environment.check_in!

    assert_equal environment, Runners::Allocator.acquire!(session)
    assert_equal 1, environments.count
    assert_equal 1, @adapter.calls.count { |call| call.first == :provision }, "one machine was asked for"
    assert_equal 1, @adapter.calls.count { |call| call.first == :inject_bootstrap }, "and installed on once"
  end

  # == step 1: a free environment ==

  test "an idle, heard environment is taken before a new one is made, the lowest id first" do
    first = create(:runner_environment, :allocated, runner: @runner, state: "idle", last_heartbeat_at: Time.current)
    create(:runner_environment, :allocated, runner: @runner, state: "idle", last_heartbeat_at: Time.current)
    session = runner_session

    assert_equal first, Runners::Allocator.acquire!(session)
    assert_equal session.id, first.reload.current_session_id
    assert_equal first.id, session.reload.runner_environment_id
    assert_empty @adapter.calls.select { |call| call.first == :provision }
  end

  test "an idle environment that is not heard, or is held, is not taken" do
    create(:runner_environment, :allocated, runner: @runner, state: "idle", last_heartbeat_at: 5.minutes.ago)
    held = create(:runner_environment, :allocated, runner: @runner, state: "idle", last_heartbeat_at: Time.current)
    create(:runner_session, :holding, environment: held)
    @runner.update!(max_environments: 3)

    assert_raises(Runners::Allocator::Pending) { Runners::Allocator.acquire!(runner_session) }

    assert_equal 3, environments.count, "a third was made"
  end

  # == the max_environments count ==

  test "the count includes an environment being torn down or failed, and not one that is gone" do
    create(:runner_environment, :allocated, runner: @runner, state: "tearing_down")
    failed = create(:runner_environment, :allocated, runner: @runner, state: "failed")

    error = assert_raises(ContainerRuntime::CapacityError) { Runners::Allocator.acquire!(runner_session) }

    assert_equal "runner_capacity", error.reason
    assert_equal "Waiting for an environment of runner \"Cloud farm\": it is at its limit of 2 environments.", error.message

    failed.update!(state: "gone")

    assert_raises(Runners::Allocator::Pending) { Runners::Allocator.acquire!(runner_session) }
    assert_equal 1, environments.not_gone.where.not(state: "tearing_down").count
  end

  test "a runner with no max_environments is limited by its max_concurrency" do
    @runner.update!(max_environments: nil, max_concurrency: 1)
    create(:runner_environment, :allocated, runner: @runner, state: "booting")

    error = assert_raises(ContainerRuntime::CapacityError) { Runners::Allocator.acquire!(runner_session) }

    assert_includes error.message, "limit of 1 environment."
  end

  # == the integration has nothing to give / the build fails ==

  test "a lack of capacity from the type's adapter is a capacity wait, and the environment stays with no machine and no clock" do
    @adapter.exhausted = "The integration has no capacity left."
    session = runner_session

    error = assert_raises(ContainerRuntime::CapacityError) { Runners::Allocator.acquire!(session) }

    assert_equal "runner_capacity", error.reason
    assert_equal "The integration has no capacity left.", error.message
    environment = environments.sole
    assert_equal "provisioning", environment.state
    assert_nil environment.external_id
    assert_nil environment.boot_started_at
    assert_equal session.id, environment.current_session_id, "the reservation is kept"
  end

  test "an environment that could not be built fails with the message, and the session's acquire raises it" do
    @adapter.provision_error = "The template needs a parameter."
    session = runner_session

    error = assert_raises(Runners::ProvisionError) { Runners::Allocator.acquire!(session) }

    assert_equal "The template needs a parameter.", error.message
    environment = environments.sole
    assert_equal "failed", environment.state
    assert_equal "The template needs a parameter.", environment.state_reason
    assert_nil environment.current_session_id
  end

  # == a revoked runner ==

  test "a revoked runner takes no session, with the message a launch gives, and makes no environment" do
    session = runner_session
    @runner.revoke!

    error = assert_raises(Runners::Machines::NoMachine) { Runners::Allocator.acquire!(session) }

    assert_equal "Runner \"Cloud farm\" is revoked. Pick another runner for the session.", error.message
    assert_empty environments
  end

  # == release, fail and let go, through the type's adapter ==

  test "release! hands the environment to its adapter, which tears it down and ends in gone" do
    session = runner_session
    environment = create(:runner_environment, :allocated, runner: @runner, state: "idle", last_heartbeat_at: Time.current)
    Runners::Allocator.acquire!(session)

    Runners::Allocator.release!(environment, session, failed: false, runtime: nil)

    assert_equal "gone", environment.reload.state
    assert_nil environment.current_session_id
    assert_equal [ :release, environment.id, false ], @adapter.calls.find { |call| call.first == :release }
  end

  test "fail! with a holder leaves an environment that another session holds now" do
    environment = create(:runner_environment, :allocated, runner: @runner, state: "idle", last_heartbeat_at: Time.current)
    late = runner_session
    holder = runner_session
    Runners::Allocator.acquire!(holder)

    Runners::Allocator.fail!(environment, "a late failure", holder: late)

    assert_equal "idle", environment.reload.state
    assert_equal holder.id, environment.current_session_id

    Runners::Allocator.fail!(environment, "its own failure")

    assert_equal "gone", environment.reload.state, "failed, then torn down by the adapter"
    assert_equal "its own failure", environment.state_reason
  end

  test "let_go! clears the hold of a session and nothing else, and only while it holds" do
    environment = create(:runner_environment, :allocated, runner: @runner, state: "idle", last_heartbeat_at: Time.current)
    session = runner_session
    Runners::Allocator.acquire!(session)

    Runners::Allocator.let_go!(runner_session)
    assert_equal session.id, environment.reload.current_session_id

    Runners::Allocator.let_go!(session)

    assert_nil environment.reload.current_session_id
    assert_equal "idle", environment.state
  end

  test "free! returns an in-service environment to rotation only while the session holds it" do
    environment = create(:runner_environment, :allocated, runner: @runner, state: "idle", last_heartbeat_at: Time.current)
    session = runner_session
    Runners::Allocator.acquire!(session)

    Runners::Allocator.free!(environment, runner_session)
    assert_equal session.id, environment.reload.current_session_id

    Runners::Allocator.free!(environment, session)
    assert_nil environment.reload.current_session_id
  end

  # == the sweep of stale sessions ==

  test "the sweep hands an environment held by a session that ended to its adapter" do
    environment = create(:runner_environment, :allocated, runner: @runner, state: "idle", last_heartbeat_at: Time.current)
    session = create(:runner_session, environment: @carrier, runner_environment: nil, state: "failed")
    Runners::Allocator.acquire!(session)

    counts = Runners::Allocator.sweep_abandoned!

    assert_equal({ checked: 1, reset_sent: 0, released: 1, failed: 0, errors: 0 }, counts)
    assert_equal "gone", environment.reload.state
  end
end
