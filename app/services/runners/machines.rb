# frozen_string_literal: true

module Runners
  # Which machine of a runner takes a session, until Runners::Allocator
  # (docs/design/agent-runtimes/DESIGN.md §7.3, §15 task 11) replaces it with
  # the scrub escalation: a free registered machine, one session per machine
  # (task 8a, decision 2).
  #
  #   environment = Runners::Machines.acquire!(session)            # raises CapacityError when every machine is busy
  #   Runners::Machines.release!(environment, session)             # after its env.scrub or env.reset succeeded
  #   Runners::Machines.let_go!(session)                           # a revoked or retired runner's session: the machine is free
  #   Runners::Machines.fail!(environment, reason, holder: session) # its env.reset failed: out of rotation
  #   Runners::Machines.sweep_abandoned!                           # machines of sessions whose cleanup will never run: env.reset, then free or failed
  #   Runners::Machines.availability(runner)                       # => Availability, for the launch's checks
  #
  # A machine is held through runner_environments.current_session_id, set
  # under the machine's row lock, so two sessions never take one machine; the
  # session records the machine it ran on in terminal_sessions.runner_environment_id.
  # Runners::Operations.enqueue! checks the hold under the same lock, so a
  # session's op is created only while it holds the machine. A machine that is
  # not heard within 90 s (RunnerEnvironment.heard; a machine running an op
  # sends heartbeats, §6.7) is offline and is given no session (task 12c).
  #
  # A machine is `failed` (§5.2) only for a failure of its own or of its runner:
  # a reset that failed, a check-in that reports missing prerequisites, a
  # refresh token presented twice. It is then held by no session, so nothing
  # that happens to the session, its deletion included, returns it to rotation,
  # and nothing returns it but a Revoke and a new Add machine. A session's
  # outcome never fails a machine: any number of failed sessions in a row leave
  # it in rotation once its reset succeeded.
  module Machines
    # Whether a runner has a machine that can take a session: `:available`
    # (one registered and reachable, free or busy), `:all_offline` (some
    # registered, none reachable, with the offline machines for the message),
    # `:none_registered`, or `:all_failed`, with the machines that are out of
    # rotation, `failed`, for the message.
    Availability = Data.define(:status, :failed, :offline) do
      def available? = status == :available
    end

    # The runner has no machine that can take a session (DESIGN.md §8,
    # `runner_unreachable`): none registered, every one `failed`, or every
    # registered one offline.
    class NoMachine < StandardError
      def reason = UNREACHABLE
    end

    UNREACHABLE = "runner_unreachable"

    # The wait reason of ContainerRuntime::CapacityError when every machine that
    # can take a session is busy (SessionAdmission::WAIT_REASONS, §10).
    RUNNER_CAPACITY = "runner_capacity"

    module_function

    # The machine the session holds, or a free one it takes now. Every machine
    # busy raises ContainerRuntime::CapacityError, which the admitted container
    # workflow answers by waiting (`capacity_wait`); no machine that can take a
    # session raises NoMachine. Two attempts for one session (a retried create)
    # get the same machine: the one that loses the race on the hold's unique
    # index answers the winner's.
    def acquire!(session)
      held = held_by(session)
      return held if held

      take!(session)
    rescue ActiveRecord::RecordNotUnique
      held_by(session) || raise
    end

    # Frees the machine once the session's `env.scrub` or `env.reset` succeeded.
    # The session's outcome is not counted: a session that failed does not
    # fail the machine, whose reset says whether it is fit. Only while
    # `session` holds the machine.
    def release!(environment, session)
      RunnerEnvironment.transaction do
        held = RunnerEnvironment.where(id: environment.id, current_session_id: session.id, state: "registered")
                                .lock.first
        held&.update!(current_session_id: nil, state_reason: nil)
      end
    end

    # The machine the session holds stops holding it, for a session whose
    # runner is revoked or deleted, whose machine no `env.scrub` will ever
    # answer. Under the machine's row lock, and only
    # while the session holds it. A machine holds at most one session
    # (`current_session_id` is unique), so there is one row. Saved, not written
    # past the model, so its callback tells the relay.
    def let_go!(session)
      RunnerEnvironment.transaction do
        held = RunnerEnvironment.where(runner_id: session.runner_id, current_session_id: session.id).lock.first
        held&.update!(current_session_id: nil)
      end
    end

    # Takes the machine out of rotation: `failed`, held by no session, with the
    # reason for people in state_reason. With a `holder`, only while that
    # session still holds it, as #release! does: a late failure of a session
    # that has since released the machine leaves the next session's hold alone.
    # Without one (a reused refresh token or a failed check-in), whoever holds it. A machine already
    # gone stays gone.
    def fail!(environment, reason, holder: nil)
      RunnerEnvironment.transaction do
        scope = RunnerEnvironment.where(id: environment.id)
        scope = scope.where(current_session_id: holder.id) if holder
        locked = scope.lock.first
        next unless locked&.may_mark_failed?

        locked.mark_failed!(reason)
      end
    end

    def held_by(session)
      RunnerEnvironment.find_by(current_session_id: session.id)
    end

    def availability(runner)
      registered = RunnerEnvironment.where(runner_id: runner.id, state: "registered")
      return Availability.new(status: :available, failed: [], offline: []) if registered.heard.exists?

      offline = registered.order(:id).to_a
      return Availability.new(status: :all_offline, failed: [], offline: offline) if offline.any?

      failed = RunnerEnvironment.where(runner_id: runner.id, state: "failed").order(:id).to_a
      Availability.new(status: failed.empty? ? :none_registered : :all_failed, failed: failed, offline: [])
    end

    # Why the runner cannot take a session, for a result that is not
    # `:available`. `pick_from` names where another runner is picked.
    def unavailable_message(runner, availability, pick_from = nil)
      elsewhere = pick_from ? " #{pick_from}" : ""
      case availability.status
      when :all_offline
        machines = availability.offline
        listed = machines.map { |machine| machine.display_name.presence || machine.key }
        "Runner \"#{runner.name}\" has no machine online: #{machines.one? ? 'its machine is' : 'every machine is'} offline " \
          "(#{listed.join(', ')}). Start aixle-runner on #{machines.one? ? 'it' : 'one of them'}, or pick another runner#{elsewhere}."
      when :none_registered
        "Runner \"#{runner.name}\" has no machine registered. Register a machine on it, or pick another runner#{elsewhere}."
      when :all_failed
        machines = availability.failed
        listed = machines.map { |machine| "#{label(machine)} (#{out_of_rotation_reason(machine)})" }
        "Runner \"#{runner.name}\" has no machine that can take a session: " \
          "#{machines.one? ? 'its machine is out of rotation' : 'every machine is out of rotation'}: #{listed.join('; ')}. " \
          "A failed machine stays out until it is revoked: revoke it on the runner page and register the host again with Add machine, or pick another runner#{elsewhere}."
      else
        raise ArgumentError, "runner \"#{runner.name}\" is available"
      end
    end

    # The machines held by a session whose cleanup will never run (a stale
    # session: its workflow ended without one, so nothing resets its machine),
    # settled one by one (#settle_abandoned!), by the schedule every minute
    # (Workflows::RunnerAbandonedMachinesSweepWorkflow). It never waits for an
    # op: it creates op rows and reads their outcomes, so a silent machine
    # holds up nothing, and a reset has the lifecycle budget. An error on one
    # machine is logged and does not stop the others; the next run tries again.
    #
    # Answers how many machines were looked at, how many a reset was sent to,
    # how many were freed or failed, and how many raised.
    def sweep_abandoned!
      counts = { checked: 0, reset_sent: 0, released: 0, failed: 0, errors: 0 }
      RunnerEnvironment.held_by_abandoned_session.pluck(:id).each do |id|
        counts[:checked] += 1
        outcome = settle_abandoned!(id)
        counts[outcome] += 1 if counts.key?(outcome)
      rescue StandardError => e
        counts[:errors] += 1
        Rails.logger.error("[Runners::Machines] abandoned machine #{id}: #{e.class}: #{e.message}")
        Sentry.capture_exception(e, extra: { runner_environment_id: id })
      end
      counts
    end

    # One machine of a stale session, under its row lock, which an enqueue
    # takes too, so two runs never send two resets. The latest `env.reset` sent
    # for that session says what is next:
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

    def settle_by(environment, session, operation)
      if operation&.completed?
        release!(environment, session)
        :released
      elsif operation&.failed?
        fail!(environment, "#{label(environment)} failed to reset after stale session #{session.id}: #{failure_text(operation.result)}",
              holder: session)
        :failed
      elsif operation&.expired?
        fail!(environment, "#{label(environment)} failed to reset after stale session #{session.id}: the runner did not answer",
              holder: session)
        :failed
      elsif environment.heard?
        deadline = Settings.runners.lifecycle_op_timeout.to_f.seconds.from_now
        Operations.enqueue!(environment, op: "env.reset", payload: {}, deadline_at: deadline, session: session)
        :reset_sent
      else
        :untouched
      end
    end
    private_class_method :settle_by

    def label(environment)
      environment.display_name.presence || environment.key
    end

    # "<class>: <message>" of an op result that carries an error.
    def failure_text(result)
      error = result&.dig("error") || {}
      [ error["class"], error["message"] ].compact_blank.join(": ").presence || "no reason given"
    end

    def out_of_rotation_reason(machine)
      machine.state_reason.presence || "no reason recorded"
    end
    private_class_method :out_of_rotation_reason

    # The runner is locked first, in the one order every issuer and revoker
    # uses (runner, then environment): a Revoke either waits for this
    # acquisition and finds the hold it made, or commits first and the
    # acquisition refuses a revoked or deleted runner with the Resolver's
    # message (§9.3).
    def take!(session)
      # A savepoint of its own, so a lost race on the hold's unique index
      # leaves a caller's transaction usable for #acquire!'s second look.
      RunnerEnvironment.transaction(requires_new: true) do
        runner = Runner.lock("FOR SHARE").find(session.runner_id)
        refuse_revoked!(runner, session)
        environment = RunnerEnvironment.free.heard.where(runner_id: runner.id).order(:id)
                                       .lock("FOR UPDATE SKIP LOCKED").first
        if environment.nil?
          availability = availability(runner)
          wait_while_offline!(runner, session, availability)
          raise NoMachine, unavailable_message(runner, availability) unless availability.available?

          # Only the machines that can take a session are counted: a `failed`
          # or an offline one does not by itself.
          busy = RunnerEnvironment.where(runner_id: runner.id, state: "registered").heard.count
          raise ContainerRuntime::CapacityError.new(
            "Waiting for a free machine on runner \"#{runner.name}\" (#{busy} of #{busy} busy).", reason: RUNNER_CAPACITY
          )
        end

        environment.update!(current_session_id: session.id)
        # A write of its own, so the caller's session object, a strategy's with
        # changes of its own, is neither saved nor changed here.
        TerminalSession.where(id: session.id).update_all(runner_environment_id: environment.id, updated_at: Time.current)
        environment
      end
    end
    private_class_method :take!

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

      names = availability.offline.map { |machine| label(machine) }
      raise ContainerRuntime::CapacityError.new(
        "Waiting for a machine of runner \"#{runner.name}\": #{availability.offline.one? ? 'its machine is' : 'every machine is'} " \
        "offline (#{names.join(', ')}). The session starts when one is back and free, " \
        "and fails if none is heard within #{ContactLoss::GRACE.inspect}.",
        reason: RUNNER_CAPACITY
      )
    end
    private_class_method :wait_while_offline!

    def refuse_revoked!(runner, session)
      return unless runner.retired?

      pick_from = session.workflow_step? ? "on the workflow" : "for the session"
      Resolver.check_status!(runner, pick_from)
    rescue Resolver::Refused => e
      raise NoMachine, e.message
    end
    private_class_method :refuse_revoked!
  end
end
