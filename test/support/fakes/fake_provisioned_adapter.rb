# frozen_string_literal: true

# A provisionable runner adapter for tests, registered for the length of a test
# only (`with_fake_provisioned_adapter`): the platform makes the environment for
# the session, as `coder` will (docs/design/agent-runtimes/runner-coder.md §7.4).
# It is a real Runners::Adapter whose provisioning calls are scripted, and whose
# start path is the one a provisioned type has: Runners::Provisioning for
# `advance!`, a teardown on release and failure, and the end of registration of
# §6.1. It calls nothing outside the app.
#
#   adapter = with_fake_provisioned_adapter
#   adapter.provision_results = [ :pending, :ready ]   # what the next calls answer; the last one repeats
#   adapter.before_provision = -> (environment) { … }  # runs inside the call, before it answers
#
# `calls` records each call in order, and `workspaces` the names handed out.
class FakeProvisionedAdapter < Runners::Adapter
  attr_accessor :provision_results, :prepare_results, :before_provision, :before_install, :install_error,
                :exhausted, :provision_error
  attr_reader :calls, :torn_down

  def self.type = "coder"

  def initialize
    super
    @calls = []
    @torn_down = []
    @provision_results = [ :pending ]
    @prepare_results = [ :ready ]
    @sequence = 0
  end

  def capabilities(_runner) = Runners::Capabilities.new(provisionable: true, rebuildable: true)

  def check_health(_runner, now: Time.current) = Health.new(status: "connected", reason: nil)

  def observe(environment, now: Time.current) = environment.heard?(now) ? :running : :unknown

  def launch_refusal(_runner, pick_from: nil) = nil

  def new_environment(_runner)
    { state: "provisioning", origin: "allocated", key: "fake-#{SecureRandom.hex(4)}" }
  end

  def advance!(environment)
    @calls << [ :advance, environment.id ]
    Runners::Provisioning.advance!(environment, self)
  end

  # No machine yet: names one, as the integration's allocate does.
  def provision(environment)
    @calls << [ :provision, environment.id ]
    raise ContainerRuntime::CapacityError.new(exhausted, reason: Runners::Allocator::RUNNER_CAPACITY) if exhausted
    raise Runners::ProvisionError, provision_error if provision_error

    before_provision&.call(environment)
    @sequence += 1
    Runners::Provisioning.record_external_id!(environment, "workspace-#{environment.id}-#{@sequence}")
    next_result(provision_results)
  end

  def prepare(environment)
    @calls << [ :prepare, environment.id ]
    next_result(prepare_results)
  end

  # Mints the token the install would carry, as the real one does, so a step
  # that finds an unspent token knows the install began.
  def inject_bootstrap(environment)
    @calls << [ :inject_bootstrap, environment.id ]
    token = Runners::Credentials.mint_registration!(environment.runner, environment: environment)
    before_install&.call(environment, token)
    raise Runners::ProvisionError, install_error if install_error

    token
  end

  def release!(environment, session, failed:, runtime: nil)
    @calls << [ :release, environment.id, failed ]
    Runners::Allocator.transition!(environment, holder: session) { |locked| begin_teardown(locked) }
    teardown(environment)
  end

  def fail!(environment, reason, holder: nil)
    @calls << [ :fail, environment.id, reason ]
    Runners::Allocator.transition!(environment, holder: holder) do |locked|
      locked.mark_failed!(reason) if locked.may_mark_failed?
      begin_teardown(locked)
    end
    teardown(environment)
  end

  # §6.1 for a provisioned environment: its credentials end, the relay is told, a
  # live session fails with the machine's message, and the teardown begins.
  def end_registration!(environment, ended_by:)
    @calls << [ :end_registration, environment.id, ended_by ]
    held = nil
    RunnerEnvironment.transaction do
      Runners::Credentials.lock_runner!(environment.runner_id)
      environment.lock!
      held = environment.current_session_id
      begin_teardown(environment, ended_by)
      now = Time.current
      environment.credentials.unrevoked.update_all(revoked_at: now, updated_at: now)
    end
    Runners::RelaySignals.machine_revoked(environment.id)
    session = held && TerminalSession.find_by(id: held)
    if session
      Sessions::Lifecycle.fail_if(
        session, error_message: "Machine \"#{Runners::Machines.label(environment)}\" of runner \"#{environment.runner.name}\" was #{ended_by}."
      )
    end
    teardown(environment)
  end

  def cleanup_waits_for_unheard?(_environment) = false

  def rebuild!(environment)
    @calls << [ :rebuild, environment.id ]
    Runners::Allocator.transition!(environment) { |locked| begin_teardown(locked) }
    teardown(environment)
  end

  def settle_abandoned!(environment_id)
    environment = RunnerEnvironment.find(environment_id)
    release!(environment, environment.current_session, failed: true)
    :released
  end

  # The machine is deleted: gone at once, unless `teardown_pending` says the
  # integration has not finished.
  def teardown(environment)
    @calls << [ :teardown, environment.id ]
    @torn_down << environment.id
    Runners::Allocator.transition!(environment) { |locked| locked.finish_teardown! if locked.tearing_down? }
  end

  private

  def begin_teardown(environment, reason = nil)
    environment.begin_teardown!(reason) if environment.may_begin_teardown?
  end

  def next_result(results)
    results.size > 1 ? results.shift : results.first
  end
end

module FakeProvisionedAdapterHelper
  # Registers the fake as `coder`'s adapter for this test (the real registry
  # holds `manual` only until the Coder adapter exists) and answers it.
  def with_fake_provisioned_adapter
    adapter = FakeProvisionedAdapter.new
    Runners::Adapter.stubs(:for_type).returns(Runners::ManualAdapter.new)
    Runners::Adapter.stubs(:for_type).with("coder").returns(adapter)
    adapter
  end
end

ActiveSupport::TestCase.include(FakeProvisionedAdapterHelper)
