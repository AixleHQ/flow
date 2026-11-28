# frozen_string_literal: true

module Runners
  # One subclass per runner type (docs/design/agent-runtimes/DESIGN.md §5.1).
  # `Adapter.for(runner)` is the registry. A type without an adapter cannot be
  # created: coder arrives with §15 task 17, kubernetes with phase 6.
  class Adapter
    class UnavailableType < StandardError; end

    # What a type's health check finds (§2.5): one of Runner's health statuses,
    # `pending` for a runner whose first machine has not registered yet, and the
    # reason for people. Runners::HealthCheck applies it.
    Health = Data.define(:status, :reason)

    # A refusal to launch a session on a runner: the reason is one of
    # Runners::Resolver::REASONS, the message is for people (§10).
    Refusal = Data.define(:reason, :message)

    REGISTRY = { "manual" => "Runners::ManualAdapter" }.freeze

    class << self
      def for(runner) = for_type(runner.runner_type)

      def for_type(type)
        name = REGISTRY[type.to_s]
        raise UnavailableType, "#{type.presence || 'This'} runners are not available yet" if name.nil?

        name.constantize.new
      end

      def available_types = REGISTRY.keys

      def type = raise(NotImplementedError)
      def config_schema = ConfigSchema.for_type(type)
    end

    def type = self.class.type
    def config_schema = self.class.config_schema

    # The behaviour layer: what the type does, which for coder and kubernetes
    # calls their APIs. The config rules are not here: they are data and pure
    # functions in ConfigSchema, which `Runner`'s validation calls.
    def capabilities(_runner) = raise(NotImplementedError)

    # The runner's health from what the platform already knows, with no
    # outbound call for a `manual` runner (§2.5, §5). Returns a Health.
    def check_health(_runner, now: Time.current) = raise(NotImplementedError)

    # What the platform knows of a machine's session container without asking
    # the machine (§5.1): `:running` while the machine is heard, `:unknown` when
    # it is not, and `:missing` for a type that can tell a removed machine from
    # one that is off. Runners::ContactLoss and the dead-container scan read it.
    def observe(_environment, now: Time.current) = raise(NotImplementedError)

    # -- The start path (runner-coder.md §7.4) --------------------------------
    #
    # What differs between types on the way a session gets an environment and
    # gives it back. Runners::Allocator and ContainerRuntime::RunnerRuntime take
    # the locks, hold the environment for the session and count
    # `max_environments`; they check no type, no capability and no policy, and
    # call these. Each is idempotent on the environment. A method that does IO
    # is called outside the allocator's runner lock.

    # Why a session cannot be launched on the runner now: nil, or a Refusal
    # (`runner_unreachable` and the message that names what is wrong).
    # `pick_from` says where another runner is picked, for the message.
    def launch_refusal(_runner, pick_from: nil) = raise(NotImplementedError)

    # The attributes of a new environment row, when this type can make one for a
    # session that finds none free (`state`, `origin`, `key`, and what else the
    # row needs), or nil when it cannot: the allocator then asks
    # #wait_for_environment!.
    def new_environment(_runner) = raise(NotImplementedError)

    # One step toward the environment being ready for the session that holds it:
    # `:ready` or `:pending`, or raises Runners::ProvisionError (the environment
    # failed) or ContainerRuntime::CapacityError (the wait goes on).
    def advance!(_environment) = raise(NotImplementedError)

    # The session that held the environment is done with it (after its container
    # was stopped): clean the environment and give it back, or delete it. Does
    # not count the session's outcome: `failed` says how the session ended, which
    # is for the cleanup level only. `runtime` is the RunnerRuntime that carries
    # out the operations of the cleanup.
    def release!(_environment, _session, failed:, runtime:) = raise(NotImplementedError)

    # The environment itself failed (its reset, its check-in, its credentials):
    # take it out of rotation with the reason for people. With a `holder`, only
    # while that session still holds it.
    def fail!(_environment, _reason, holder: nil) = raise(NotImplementedError)

    # An environment's registration ends (a Revoke of it, its own `unregister`,
    # or its runner revoked or deleted): end its credentials and the session it
    # holds, and take it out for good (§6.1). `ended_by` is how the message to a
    # live session says it left.
    def end_registration!(_environment, ended_by:) = raise(NotImplementedError)

    # Whether the session's cleanup waits for an environment that is not heard
    # (RunnerRuntime#cleanup_ready?), because the environment will be heard
    # again, rather than going on without it.
    def cleanup_waits_for_unheard?(_environment) = raise(NotImplementedError)

    # Replace a failed environment. Raises Runners::UnsupportedOperation for a
    # type that cannot.
    def rebuild!(_environment) = raise(NotImplementedError)

    # Step 3 of Allocator.acquire!, when the type makes no new environment and
    # none is free: raises ContainerRuntime::CapacityError so the session waits,
    # or Runners::Machines::NoMachine when the runner has nothing that can take
    # a session. The default is the wait for a free environment.
    def wait_for_environment!(runner, _session)
      raise ContainerRuntime::CapacityError.new(
        "Waiting for a free environment on runner \"#{runner.name}\".", reason: Allocator::RUNNER_CAPACITY
      )
    end

    # An environment held by a session whose cleanup will never run (its
    # workflow ended without one), settled by Allocator.sweep_abandoned! under no
    # lock of ours: answers `:released`, `:failed`, `:reset_sent` or
    # `:untouched`. Never waits for an operation.
    def settle_abandoned!(_environment_id) = raise(NotImplementedError)
  end
end
