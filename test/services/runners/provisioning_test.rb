# frozen_string_literal: true

require "test_helper"

# Runners::Provisioning.advance! (docs/design/agent-runtimes/runner-coder.md
# §5.2) with a fake adapter: the step of each state, the timeout counted from the
# first external id, the install that runs once, and the races with a session that
# is cancelled and with the runner registering.
class Runners::ProvisioningTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :coder, name: "Cloud farm", max_environments: 3)
    @adapter = with_fake_provisioned_adapter
    @environment = create(:runner_environment, :allocated, runner: @runner)
    @session = create(:runner_session, environment: @environment, runner_environment: nil)
    @environment.update!(current_session: @session)
  end

  def advance(environment = @environment) = Runners::Provisioning.advance!(environment, @adapter)

  def timeout = Settings.runners.bootstrap_timeout.to_f.seconds

  # == provisioning ==

  test "with no external id it asks for a machine and records its name, and the clock starts then" do
    travel_to Time.zone.local(2026, 11, 28, 10) do
      assert_equal :pending, advance

      @environment.reload
      assert_equal "workspace-#{@environment.id}-1", @environment.external_id
      assert_equal Time.current, @environment.boot_started_at
    end
    assert_equal [ :provision ], @adapter.calls.map(&:first) - [ :advance ]
  end

  test "a later write of the name leaves the clock where it was" do
    started = Time.zone.local(2026, 11, 28, 10)
    travel_to(started) { advance }

    travel_to(started + 5.minutes) { Runners::Provisioning.record_external_id!(@environment, "another-name") }

    @environment.reload
    assert_equal "another-name", @environment.external_id
    assert_equal started, @environment.boot_started_at
  end

  test "with a machine named it prepares, and waits until the machine is ready" do
    @adapter.prepare_results = [ :pending, :ready ]
    advance

    assert_equal :pending, advance
    assert_equal "provisioning", @environment.reload.state
    assert_empty @adapter.calls.select { |call| call.first == :inject_bootstrap }

    assert_equal :pending, advance
    assert_equal "booting", @environment.reload.state, "ready: the install ran and the build is done"
  end

  test "the install runs once, with a token bound to the environment, and the redelivery of the step does not install again" do
    advance
    advance
    token = RunnerCredential.where(runner_environment: @environment, kind: "registration").sole

    assert_equal @environment.id, token.runner_environment_id
    assert_nil token.used_at
    assert_equal 1, @adapter.calls.count { |call| call.first == :inject_bootstrap }

    advance
    assert_equal 1, @adapter.calls.count { |call| call.first == :inject_bootstrap }
  end

  test "an install that was interrupted, leaving an unspent token on a provisioning row, fails the environment and does not install twice" do
    advance
    Runners::Credentials.mint_registration!(@runner, environment: @environment)
    @adapter.prepare_results = [ :ready ]

    error = assert_raises(Runners::ProvisionError) { advance }

    assert_equal "The install on workspace #{@environment.reload.external_id} was interrupted.", error.message
    assert_equal "failed", @environment.state
    assert_equal error.message, @environment.state_reason
    assert_empty @adapter.calls.select { |call| call.first == :inject_bootstrap }
  end

  test "an install the adapter refuses fails the environment with its message" do
    @adapter.install_error = "The workspace has no systemd, which the runner service needs"
    advance

    error = assert_raises(Runners::ProvisionError) { advance }

    assert_equal "The workspace has no systemd, which the runner service needs", error.message
    assert_equal "failed", @environment.reload.state
    assert_nil @environment.current_session_id, "the failed environment holds no session"
  end

  test "the runner registering while the install call is in flight moves the row once, and the step fires no second transition" do
    advance
    @adapter.before_install = lambda do |environment, token|
      credential = RunnerCredential.find_by_token(token, kind: :registration)
      Runners::Registration.register!(credential, name: environment.external_id, os: "linux", arch: "amd64", facts: {},
                                                  auto_update: true, runner_version: "1.4.0", protocol_version: "1")
    end

    assert_nothing_raised { advance }

    @environment.reload
    assert_equal "booting", @environment.state
    assert_equal @environment.external_id, @environment.display_name
  end

  # == the timeout ==

  test "the timeout is counted from the first external id, and nothing is timed out before one" do
    travel_to(Time.zone.local(2026, 11, 28, 10)) do
      @adapter.exhausted = "No capacity."
      assert_raises(ContainerRuntime::CapacityError) { advance }
    end
    travel_to(Time.zone.local(2026, 11, 28, 10) + (3 * timeout)) do
      assert_raises(ContainerRuntime::CapacityError) { advance }
      assert_equal "provisioning", @environment.reload.state, "no machine, no clock"
    end
  end

  test "a build that outlives the timeout fails the environment with the message of the build" do
    @adapter.prepare_results = [ :pending ]
    started = Time.zone.local(2026, 11, 28, 10)
    travel_to(started) { advance }

    travel_to(started + timeout - 1.second) { assert_equal :pending, advance }
    error = travel_to(started + timeout) { assert_raises(Runners::ProvisionError) { advance } }

    assert_equal "The workspace was not ready within 15 min.", error.message
    assert_equal "failed", @environment.reload.state
  end

  test "an environment that does not check in in time fails with the message that names the platform" do
    started = Time.zone.local(2026, 11, 28, 10)
    travel_to(started) { advance }
    travel_to(started + 1.minute) { advance }
    assert_equal "booting", @environment.reload.state

    travel_to(started + 14.minutes) { assert_equal :pending, advance }
    error = travel_to(started + timeout + 1.minute) { assert_raises(Runners::ProvisionError) { advance } }

    assert_equal "Workspace started but aixle-runner did not check in within 15 min. " \
                 "Check that the workspace can reach #{Settings.domain}:443.", error.message
    assert_equal "failed", @environment.reload.state
    assert_equal error.message, @environment.state_reason
  end

  # == the other states ==

  test "an idle environment is ready" do
    @environment.update!(state: "idle")

    assert_equal :ready, advance
    assert_empty @adapter.calls.reject { |call| call.first == :advance }
  end

  test "a failed environment, or one being torn down, cannot be had: the session fails with its reason" do
    @environment.update!(state: "failed", state_reason: "the install failed")

    error = assert_raises(Runners::ProvisionError) { advance }
    assert_equal "The environment failed: the install failed", error.message

    @environment.update!(state: "tearing_down", state_reason: nil)
    error = assert_raises(Runners::ProvisionError) { advance }
    assert_equal "The environment tearing down", error.message
  end

  # == a session that is cancelled meanwhile ==

  test "a session cancelled while the environment is provisioning, and while it is booting, ends the environment gone" do
    advance
    Runners::Allocator.release!(@environment, @session, failed: true, runtime: nil)
    assert_equal "gone", @environment.reload.state
    assert_nil @environment.current_session_id

    booting = create(:runner_environment, :allocated, runner: @runner, state: "booting")
    other = create(:runner_session, environment: booting, runner_environment: nil)
    booting.update!(current_session: other)

    Runners::Allocator.release!(booting, other, failed: true, runtime: nil)

    assert_equal "gone", booting.reload.state
  end

  test "a session cancelled while the machine is being asked for leaves the environment gone, and the late machine's name is only recorded" do
    @adapter.before_provision = lambda do |environment|
      Runners::Allocator.release!(environment, @session, failed: true, runtime: nil)
    end

    assert_equal :pending, advance

    @environment.reload
    assert_equal "gone", @environment.state
    assert @environment.external_id.present?, "the late workspace is recorded for the sweep to find"
    assert_nil @environment.current_session_id
  end
end
