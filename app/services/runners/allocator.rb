# frozen_string_literal: true

module Runners
  # Which environment of a runner a session holds, for every runner type
  # (docs/design/agent-runtimes/runner-coder.md §5): taking a free one or making
  # a new one, setting and clearing the hold, the lock order and the
  # `max_environments` count. What differs between types is a method of
  # Runners::Adapter (§7.4), called from here and from ContainerRuntime::RunnerRuntime,
  # which check no type, no capability and no policy.
  #
  #   environment = Runners::Allocator.acquire!(session)                      # held and ready, or raises
  #   Runners::Allocator.release!(environment, session, failed:, runtime:)    # the session is done with it
  #   Runners::Allocator.let_go!(session)                                     # a revoked or retired runner's session: the hold goes
  #   Runners::Allocator.fail!(environment, reason, holder: nil)              # the environment itself failed
  #   Runners::Allocator.sweep_abandoned!                                     # environments of sessions whose cleanup will never run
  #
  # An environment is held through runner_environments.current_session_id, set
  # under the environment's row lock, with a unique index, so two sessions never
  # take one environment; the session records the environment it ran on in
  # terminal_sessions.runner_environment_id. Runners::Operations.enqueue! checks
  # the hold under the same lock, so a session's op is created only while it
  # holds the environment. An environment that is not heard within 90 s
  # (RunnerEnvironment.heard) is offline and is given no session.
  #
  # An environment fails (`failed`) only for a failure of its own or of its
  # runner: a reset that failed, a check-in that reports missing prerequisites, a
  # refresh token presented twice, a build that did not finish. A session's
  # outcome never fails an environment, and the allocator keeps no failure count.
  #
  # The locks are taken in one order, every issuer and revoker's: the runner
  # (`FOR UPDATE` here, for every type, so the count of `acquire!`'s step 2 is
  # serial), then the environment, then its credentials.
  module Allocator
    # The wait reason of ContainerRuntime::CapacityError when no environment can
    # take the session and none can be made (SessionAdmission::WAIT_REASONS).
    RUNNER_CAPACITY = Machines::RUNNER_CAPACITY
    # The wait reason while the platform brings the session's environment up.
    RUNNER_PROVISIONING = "runner_provisioning"

    # The session's environment is not ready yet: the phase keeps its
    # reservation and tries again (`capacity_wait`, 30 s later).
    class Pending < ContainerRuntime::CapacityError
      def initialize(message)
        super(message, reason: RUNNER_PROVISIONING)
      end
    end

    module_function

    # The environment the session holds, or a free one it takes now, or one it
    # makes (§5.1). Raises ContainerRuntime::CapacityError, which the admitted
    # container workflow answers by waiting (`capacity_wait`), when nothing is
    # free and nothing can be made, and Pending until the environment is ready;
    # Machines::NoMachine when the runner has nothing that can take a session.
    # Two attempts for one session (a retried create) get the same environment:
    # the one that loses the race on the hold's unique index answers the
    # winner's. The adapter advances the environment once after the lock is
    # released (its IO is outside the runner lock).
    def acquire!(session)
      environment = held_by(session) || take_or_find!(session)
      ready!(environment)
      environment
    end

    # Frees the environment once the session's cleanup succeeded: the hold is
    # cleared and it stays in service. Only while `session` holds it. The
    # session's outcome is not counted. What a type does besides is its
    # adapter's (`Adapter#release!`, which calls this for `manual`).
    def release!(environment, session, failed:, runtime:)
      adapter_for(environment).release!(environment, session, failed: failed, runtime: runtime)
    end

    # The hold goes and nothing else: the environment is in service again.
    # Under the environment's row lock, and only while `session` holds it and
    # the environment is in service.
    def free!(environment, session)
      RunnerEnvironment.transaction do
        held = RunnerEnvironment.where(id: environment.id, current_session_id: session.id,
                                       state: RunnerEnvironment::IN_SERVICE_STATES).lock.first
        held&.update!(current_session_id: nil, state_reason: nil)
      end
    end

    # The environment the session holds stops holding it, for a session whose
    # runner is revoked or deleted, whose environment nothing will ever answer.
    # Under the environment's row lock, and only while the session holds it. An
    # environment holds at most one session (`current_session_id` is unique), so
    # there is one row. Saved, not written past the model, so its callback tells
    # the relay.
    def let_go!(session)
      RunnerEnvironment.transaction do
        held = RunnerEnvironment.where(runner_id: session.runner_id, current_session_id: session.id).lock.first
        held&.update!(current_session_id: nil)
      end
    end

    # The environment itself failed, with the reason for people. With a `holder`,
    # only while that session still holds it (a late failure of a session that has
    # since released the environment leaves the next session's hold alone);
    # without one, whoever holds it. What the failure does to the environment is
    # its adapter's (`Adapter#fail!`).
    def fail!(environment, reason, holder: nil)
      adapter_for(environment).fail!(environment, reason, holder: holder)
    end

    # The common part of an adapter's change to one environment: the row, locked,
    # re-read, and (with a `holder`) only while that session holds it. Yields the
    # locked environment; answers the block's value, or nil when the row is gone
    # or the session no longer holds it.
    def transition!(environment, holder: nil)
      RunnerEnvironment.transaction do
        scope = RunnerEnvironment.where(id: environment.id)
        scope = scope.where(current_session_id: holder.id) if holder
        locked = scope.lock.first
        yield locked if locked
      end
    end

    def held_by(session)
      RunnerEnvironment.find_by(current_session_id: session.id)
    end

    # The environments held by a session whose cleanup will never run (a stale
    # session: its workflow ended without one, so nothing cleans its
    # environment), settled one by one by their adapter (`Adapter#settle_abandoned!`),
    # by the schedule every minute (Workflows::RunnerAbandonedMachinesSweepWorkflow).
    # It never waits for an op: it creates op rows and reads their outcomes, so a
    # silent machine holds up nothing. An error on one environment is logged and
    # does not stop the others; the next run tries again.
    #
    # Answers how many environments were looked at, how many a reset was sent to,
    # how many were freed or failed, and how many raised.
    def sweep_abandoned!
      counts = { checked: 0, reset_sent: 0, released: 0, failed: 0, errors: 0 }
      RunnerEnvironment.held_by_abandoned_session.includes(:runner).find_each do |environment|
        counts[:checked] += 1
        outcome = Adapter.for(environment.runner).settle_abandoned!(environment.id)
        counts[outcome] += 1 if counts.key?(outcome)
      rescue StandardError => e
        counts[:errors] += 1
        Rails.logger.error("[Runners::Allocator] abandoned environment #{environment.id}: #{e.class}: #{e.message}")
        Sentry.capture_exception(e, extra: { runner_environment_id: environment.id })
      end
      counts
    end

    def adapter_for(environment) = Adapter.for(environment.runner)
    private_class_method :adapter_for

    def take_or_find!(session)
      take!(session)
    rescue ActiveRecord::RecordNotUnique
      held_by(session) || raise
    end
    private_class_method :take_or_find!

    # The adapter's step, once, outside the runner lock: `:ready`, or Pending.
    def ready!(environment)
      adapter = adapter_for(environment)
      return if adapter.advance!(environment) == :ready

      environment.reload
      raise Pending, "Starting an environment on runner \"#{environment.runner.name}\" (#{environment.state.to_s.humanize(capitalize: false)})."
    end
    private_class_method :ready!

    # The runner is locked first, in the one order every issuer and revoker
    # uses (runner, then environment): a Revoke either waits for this acquisition
    # and finds the hold it made, or commits first and the acquisition refuses a
    # revoked or deleted runner with the Resolver's message (§9.3).
    #
    # 1. An idle, heard environment of the runner, lowest id first, taken
    #    `FOR UPDATE SKIP LOCKED`.
    # 2. Else, when the adapter makes a new environment and the runner's
    #    environments that are not `gone` number fewer than `max_environments`
    #    (null means `max_concurrency`), the row the adapter described, held by
    #    the session. `tearing_down` and `failed` rows count until they are
    #    `gone`, so a slow delete cannot let the pool grow past its limit.
    # 3. Else the adapter's wait (`manual`: its machines are busy or offline).
    def take!(session)
      # A savepoint of its own, so a lost race on the hold's unique index
      # leaves a caller's transaction usable for #take_or_find!'s second look.
      RunnerEnvironment.transaction(requires_new: true) do
        runner = Runner.lock("FOR UPDATE").find(session.runner_id)
        refuse_retired!(runner, session)
        adapter = Adapter.for(runner)

        environment = RunnerEnvironment.free.heard.where(runner_id: runner.id).order(:id)
                                       .lock("FOR UPDATE SKIP LOCKED").first
        if environment
          environment.update!(current_session_id: session.id)
        else
          environment = make!(runner, adapter, session)
        end
        # A write of its own, so the caller's session object, a strategy's with
        # changes of its own, is neither saved nor changed here.
        TerminalSession.where(id: session.id).update_all(runner_environment_id: environment.id, updated_at: Time.current)
        environment
      end
    end
    private_class_method :take!

    def make!(runner, adapter, session)
      attributes = adapter.new_environment(runner)
      adapter.wait_for_environment!(runner, session) if attributes.nil?

      limit = runner.max_environments || runner.max_concurrency
      in_use = RunnerEnvironment.where(runner_id: runner.id).not_gone.count
      if in_use >= limit
        raise ContainerRuntime::CapacityError.new(
          "Waiting for an environment of runner \"#{runner.name}\": it is at its limit of #{limit} " \
          "#{limit == 1 ? 'environment' : 'environments'}.", reason: RUNNER_CAPACITY
        )
      end

      RunnerEnvironment.create!(attributes.merge(runner: runner, company_id: runner.company_id, current_session_id: session.id))
    end
    private_class_method :make!

    def refuse_retired!(runner, session)
      return unless runner.retired?

      pick_from = session.workflow_step? ? "on the workflow" : "for the session"
      Resolver.check_status!(runner, pick_from)
    rescue Resolver::Refused => e
      raise Machines::NoMachine, e.message
    end
    private_class_method :refuse_retired!
  end
end
