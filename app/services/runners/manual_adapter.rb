# frozen_string_literal: true

module Runners
  # A machine the operator installed `aixle-runner` on. The platform creates,
  # rebuilds and calls nothing (docs/design/agent-runtimes/DESIGN.md §5.1).
  class ManualAdapter < Adapter
    # §2.5: with no registered machine heard for this long, the runner is
    # unreachable. Between RunnerEnvironment::ONLINE_WINDOW and this, a machine
    # that is not heard is offline and the runner is degraded.
    UNREACHABLE_AFTER = 3.minutes
    REASON_LIMIT = 255

    def self.type = "manual"

    def capabilities(_runner)
      Capabilities.new(provisionable: false, rebuildable: false)
    end

    # From the runner's machines alone (§2.5):
    #
    # - `pending`: no machine has ever registered;
    # - `unreachable`: no machine can take a session (every one `failed`, or
    #   every one `gone`), or no registered machine was heard for more than
    #   UNREACHABLE_AFTER;
    # - `connected`: every registered machine was heard within
    #   RunnerEnvironment::ONLINE_WINDOW and none has failed;
    # - `degraded`: any other, with the offline and failed machines named.
    def check_health(runner, now: Time.current)
      machines = runner.environments.order(:id).to_a
      return health("pending") if machines.empty?

      registered = machines.select(&:registered?)
      failed = machines.select(&:failed?)
      return health("unreachable", unusable_reason(failed)) if registered.empty?

      offline = registered.reject { |machine| machine.heard?(now) }
      return health("connected") if offline.empty? && failed.empty?

      if registered.none? { |machine| machine.heard?(now, within: UNREACHABLE_AFTER) }
        return health("unreachable", "No machine has been heard for more than #{UNREACHABLE_AFTER.inspect}: " \
                                     "#{names(offline)}.")
      end

      health("degraded", degraded_reason(offline, failed))
    end

    # `:running` while the machine is heard (RunnerEnvironment::ONLINE_WINDOW, as
    # Liveness counts it), `:unknown` after. Never `:missing`: a machine that
    # is powered off cannot be told from one that was removed (§5.1).
    def observe(environment, now: Time.current)
      environment.heard?(now) ? :running : :unknown
    end

    # -- The start path (runner-coder.md §7.4) --------------------------------

    # `manual` decides which machines exist: an operator installs them. A
    # session that finds none free waits (#wait_for_environment!).
    def new_environment(_runner) = nil

    # A registered machine is ready.
    def advance!(_environment) = :ready

    # A machine is never replaced: it is revoked and added again.
    def rebuild!(_environment)
      raise UnsupportedOperation, "A manual runner's machine cannot be rebuilt: revoke it and add the host again with Add machine."
    end

    # Cleanup waits for a machine that is not heard: the operator's machine comes
    # back, and its containers are still on it (docs/architecture/runtime-layers.md, 7).
    def cleanup_waits_for_unheard?(_environment) = true

    # The runner's own availability (Machines.availability): none registered,
    # every one failed, or every registered one offline.
    def launch_refusal(runner, pick_from: nil)
      availability = Machines.availability(runner)
      return nil if availability.available?

      Refusal.new(reason: Machines::UNREACHABLE, message: Machines.unavailable_message(runner, availability, pick_from))
    end

    # No machine is free: wait while they are busy, or offline for a session that
    # already waits and has not lapsed (DESIGN.md §7.3, §6.7); the runner with no
    # machine that can take a session is refused, as at launch.
    def wait_for_environment!(runner, session)
      availability = Machines.availability(runner)
      wait_while_offline!(runner, session, availability)
      raise Machines::NoMachine, Machines.unavailable_message(runner, availability) unless availability.available?

      # Only the machines that can take a session are counted: a `failed` or an
      # offline one does not by itself.
      busy = RunnerEnvironment.where(runner_id: runner.id, state: "registered").heard.count
      raise ContainerRuntime::CapacityError.new(
        "Waiting for a free machine on runner \"#{runner.name}\" (#{busy} of #{busy} busy).", reason: Allocator::RUNNER_CAPACITY
      )
    end

    # The machine is cleaned by the runner's policy and returns to rotation, or
    # leaves it. `container.stop` was sent by the caller. Under `reuse`,
    # `env.scrub`: the machine's containers and the session's outputs go, the
    # checkouts, caches and images stay. Under `reset`, or after a `failed`
    # session under either policy, `env.reset`: the workspace and cache volumes go
    # too. A failed scrub is followed by a reset, and the machine is free again
    # once either succeeded. A failed reset, a machine that does not answer
    # included, takes the machine out of rotation with the reason. The exception
    # is a session that lost contact whose reset expired while the machine was not
    # heard: the session keeps the machine and the cleanup sends a new reset when
    # the machine is heard again. A machine heard throughout the reset's deadline
    # that still did not answer is failed.
    def release!(environment, session, failed:, runtime:)
      if !failed && session.runner.reuse_policy == "reuse"
        scrub = runtime.lifecycle_op(session, "env.scrub", { "image" => runtime.scrub_image(session) })
        return Allocator.free!(environment, session) if scrub.ok?

        Rails.logger.warn("[ManualAdapter] session #{session.id}: #{scrub.message}; machine #{environment.key} is reset instead")
      end

      reset = runtime.lifecycle_op(session, "env.reset", {})
      return Allocator.free!(environment, session) if reset.ok?

      # A machine that is not heard when its reset expires is still away (or
      # went quiet again before it took the reset: DESIGN.md §6.7). The reset it
      # never answered says nothing of the machine's state, so the session keeps
      # the machine and the cleanup waits until it is heard again. A machine that
      # is heard and still left the reset unanswered is not away, so it is failed
      # below; otherwise a runner that heartbeats but never runs ops would hold
      # its slot and be reset without end.
      if reset.expired? && session.contact_lost? && !RunnerEnvironment.find(environment.id).heard?
        Rails.logger.warn("[ManualAdapter] session #{session.id}: #{reset.message}; machine #{environment.key} " \
                          "is not heard, so its reset is sent again when it is heard")
        return
      end

      Rails.logger.warn("[ManualAdapter] session #{session.id}: #{reset.message}; machine #{environment.key} is failed")
      reason = reset.expired? ? "the runner did not answer" : Machines.failure_text(reset.result)
      fail!(environment, "#{Machines.label(environment)} failed to reset after session #{session.id}: #{reason}", holder: session)
    end

    # Takes the machine out of rotation: `failed`, held by no session, with the
    # reason for people in state_reason. With a `holder`, only while that session
    # still holds it: a late failure of a session that has since released the
    # machine leaves the next session's hold alone. Without one (a reused refresh
    # token or a failed check-in), whoever holds it. A machine already gone stays gone.
    def fail!(environment, reason, holder: nil)
      Allocator.transition!(environment, holder: holder) do |locked|
        locked.mark_failed!(reason) if locked.may_mark_failed?
      end
    end

    # What `aixle-runner unregister` and a Revoke do (runner-coder.md §6.1): the
    # credentials are revoked, the hold is released and the row is `gone`, the
    # relay is told, and a live session ends at once with a message that names
    # the machine; its cleanup finds the machine absent and releases its admission
    # (PROTOCOL.md §9). `ended_by` is how the message says the machine left.
    def end_registration!(environment, ended_by: RunnerEnvironmentStateMachine::UNREGISTERED)
      held_session_id = release_machine!(environment, ended_by)
      RelaySignals.machine_revoked(environment.id)
      end_session(environment, held_session_id, ended_by) if held_session_id
    end

    # The machines held by a session whose cleanup will never run, settled by
    # Allocator.sweep_abandoned!: one machine of a stale session, under its row
    # lock, which an enqueue takes too, so two runs never send two resets. The
    # latest `env.reset` sent for that session says what is next:
    #
    # - none: a reset is sent as the session if the machine is heard now
    #   (`:reset_sent`), else nothing, and the next run looks again;
    # - still open: nothing;
    # - completed: the machine is free (`:released`);
    # - answered with an error: the machine is `failed`, with that error;
    # - expired: `failed`, "the runner did not answer", whether or not the
    #   runner took the reset and whether or not the machine was heard at the
    #   deadline. The sweep sends a reset only to a machine it hears, so carrying
    #   it out is the machine's own job; a runner stuck in an earlier op
    #   heartbeats but never polls ops, and would otherwise be sent a new reset
    #   every `lifecycle_op_timeout` for ever.
    #
    # Answers `:reset_sent`, `:released`, `:failed`, or `:untouched`: the machine
    # no longer qualifies (a Revoke let it go, or its session's cleanup is alive
    # after all), or nothing is to be done now.
    def settle_abandoned!(environment_id)
      RunnerEnvironment.transaction do
        environment = RunnerEnvironment.held_by_abandoned_session.lock.find_by(id: environment_id)
        next :untouched if environment.nil?

        session = environment.current_session
        operation = RunnerOperation.latest_reset(environment, session)
        next :untouched if operation&.deliverable?

        settle_by(environment, session, operation)
      end
    end

    private

    # Locks in the one order every issuer and revoker uses: the runner, then the
    # environment, then the credentials (Credentials.rotate!). Holding the runner
    # first keeps this from deadlocking with a runner Revoke, which revokes the
    # same credential rows (Runner#revoke_credentials); a rotation racing this
    # either sees the environment `gone` or has its pair revoked here. The runner
    # lock accepts a retired runner: a Revoke of the runner ends its machines
    # after the runner is retired (Credentials.lock_runner!).
    #
    # The id of the session the machine held, read under the locks.
    def release_machine!(environment, reason)
      RunnerEnvironment.transaction do
        Credentials.lock_runner!(environment.runner_id)
        environment.lock!
        held = environment.current_session_id
        environment.unregister!(reason)
        now = Time.current
        environment.credentials.unrevoked.update_all(revoked_at: now, updated_at: now)
        held
      end
    end

    def end_session(environment, session_id, ended_by)
      session = TerminalSession.find_by(id: session_id)
      return if session.nil?

      # A compare-and-set: a session that finished or was cancelled meanwhile keeps its outcome.
      Sessions::Lifecycle.fail_if(
        session,
        error_message: "Machine \"#{Machines.label(environment)}\" of runner \"#{environment.runner.name}\" was #{ended_by}."
      )
    end

    def settle_by(environment, session, operation)
      if operation&.completed?
        Allocator.free!(environment, session)
        :released
      elsif operation&.failed?
        fail!(environment, "#{Machines.label(environment)} failed to reset after stale session #{session.id}: " \
                           "#{Machines.failure_text(operation.result)}", holder: session)
        :failed
      elsif operation&.expired?
        fail!(environment, "#{Machines.label(environment)} failed to reset after stale session #{session.id}: " \
                           "the runner did not answer", holder: session)
        :failed
      elsif environment.heard?
        deadline = Settings.runners.lifecycle_op_timeout.to_f.seconds.from_now
        Operations.enqueue!(environment, op: "env.reset", payload: {}, deadline_at: deadline, session: session)
        :reset_sent
      else
        :untouched
      end
    end

    # A session that already waits for a machine (`runner_capacity`) keeps
    # waiting while the runner's machines are offline, as a hosted session
    # waits for capacity: the machine may come back. It fails with the
    # unavailable message once no machine of the runner has been heard for
    # ContactLoss::GRACE, the bound of §6.7. A launch that was not waiting
    # fails at once (§8), and so does a runner with no machine registered.
    def wait_while_offline!(runner, session, availability)
      return unless availability.status == :all_offline
      return unless session.waiting_for_runner_machine?

      now = Time.current
      return if availability.offline.all? { |machine| ContactLoss.lapsed?(machine, now: now) }

      names = availability.offline.map { |machine| Machines.label(machine) }
      raise ContainerRuntime::CapacityError.new(
        "Waiting for a machine of runner \"#{runner.name}\": #{availability.offline.one? ? 'its machine is' : 'every machine is'} " \
        "offline (#{names.join(', ')}). The session starts when one is back and free, " \
        "and fails if none is heard within #{ContactLoss::GRACE.inspect}.",
        reason: Allocator::RUNNER_CAPACITY
      )
    end

    def health(status, reason = nil) = Health.new(status: status, reason: reason&.truncate(REASON_LIMIT))

    def unusable_reason(failed)
      return "No machine registered." if failed.empty?

      "No machine can take a session: #{failed.one? ? 'its machine' : 'every machine'} failed: #{failures(failed)}."
    end

    def degraded_reason(offline, failed)
      parts = []
      parts << "Offline: #{names(offline)}." if offline.any?
      parts << "Failed: #{failures(failed)}." if failed.any?
      parts.join(" ")
    end

    def failures(machines)
      machines.map { |machine| "#{name(machine)} (#{machine.state_reason.presence || 'no reason recorded'})" }.join("; ")
    end

    def names(machines) = machines.map { |machine| name(machine) }.join(", ")

    def name(machine) = machine.display_name.presence || machine.key
  end
end
