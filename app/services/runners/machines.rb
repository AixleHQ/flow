# frozen_string_literal: true

module Runners
  # Which machine of a runner takes a session, until Runners::Allocator
  # (docs/design/agent-runtimes/DESIGN.md §7.3, §15 task 11) replaces it with
  # the scrub escalation: a free registered machine, one session per machine
  # (task 8a, decision 2).
  #
  #   environment = Runners::Machines.acquire!(session)            # raises CapacityError when every machine is busy
  #   Runners::Machines.release!(environment, session, failed:)    # after its env.scrub or env.reset succeeded
  #   Runners::Machines.fail!(environment, reason, holder: session) # its env.reset failed: out of rotation
  #   Runners::Machines.return_to_service!(environment)            # a failed machine: env.reset, then free again
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
  # A machine whose reset failed, or on which `runners.max_consecutive_failures`
  # sessions in a row failed, is `failed` (§5.2) and held by no session, so
  # nothing that happens to the session, its deletion included, returns it to
  # rotation. Return to service (§5.2, §7.2) does: it sends `env.reset` with no
  # session, the machine is `resetting` and takes no session meanwhile, and the
  # result of the op settles it (#settle_resets!): `registered` and free, or
  # `failed` with the new reason.
  module Machines
    # Whether a runner has a machine that can take a session: `:available`
    # (one registered and reachable, free or busy), `:all_offline` (some
    # registered, none reachable, with the offline machines for the message),
    # `:none_registered`, or `:all_failed`, with the machines that are out of
    # rotation, `failed` or `resetting`, for the message.
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

    # Return to service of a machine whose runner is not `manual`.
    class NotManual < StandardError; end

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

    # Frees the machine once the session's `env.scrub` or `env.reset` succeeded,
    # and counts the session: a session that `failed` adds to the machine's
    # streak, one that ended well sets it back to 0, and the machine whose
    # streak reaches `runners.max_consecutive_failures` is `failed` instead of
    # freed (§7.2), with the reason. Only while `session` holds the machine.
    def release!(environment, session, failed: false)
      RunnerEnvironment.transaction do
        held = RunnerEnvironment.where(id: environment.id, current_session_id: session.id, state: "registered")
                                .lock.first
        next unless held

        streak = failed ? held.consecutive_failures + 1 : 0
        held.consecutive_failures = streak
        if streak >= max_consecutive_failures
          held.mark_failed!("#{label(held)} failed #{streak} sessions in a row")
        else
          held.update!(current_session_id: nil, state_reason: nil)
        end
      end
    end

    # Takes the machine out of rotation: `failed`, held by no session, with the
    # reason for people in state_reason. With a `holder`, only while that
    # session still holds it, as #release! does: a late failure of a session
    # that has since released the machine leaves the next session's hold alone.
    # Without one (a reused refresh token), whoever holds it. A machine already
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

      failed = RunnerEnvironment.where(runner_id: runner.id, state: %w[failed resetting]).order(:id).to_a
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
          "Fix the machine and press Return to service on the runner page, or pick another runner#{elsewhere}."
      else
        raise ArgumentError, "runner \"#{runner.name}\" is available"
      end
    end

    # Return to service (§5.2): a `failed` machine goes `resetting`, held by no
    # session, and an `env.reset` is put on its queue. It takes no session until
    # the op settles it (#settle_resets!). False for a machine that is not
    # `failed`: pressing it twice sends one reset. Only a `manual` runner's
    # machine returns this way (NotManual): a `coder` machine's recovery may be
    # a rebuild, not a reset (§7.2).
    def return_to_service!(environment)
      raise NotManual, "Only a machine of a manual runner is returned to service." unless environment.runner.manual?

      RunnerEnvironment.transaction do
        locked = RunnerEnvironment.where(id: environment.id).lock.first
        next false unless locked&.may_begin_return_to_service?

        locked.begin_return_to_service!
        Runners::Operations.enqueue_reset!(locked, deadline_at: Settings.runners.lifecycle_op_timeout.to_f.seconds.from_now)
        true
      end
    end

    # Settles every `resetting` machine whose `env.reset` has an outcome: the
    # machine is free again when it succeeded, `failed` with the new reason when
    # it failed or expired. A machine whose op is still open stays `resetting`.
    # Called wherever an op gets its outcome, so it is idempotent.
    def settle_resets!(environment_ids = nil)
      machines = RunnerEnvironment.where(state: "resetting")
      machines = machines.where(id: environment_ids) if environment_ids
      machines.find_each { |machine| settle_reset!(machine) }
    end

    # Busy: holding a session. Total: registered and not `gone`, `failed` and
    # `resetting` ones included. For the runners page and list (§11).
    Counts = Data.define(:busy, :total)

    def counts(runners)
      ids = runners.map(&:id)
      rows = RunnerEnvironment.where(runner_id: ids).where.not(state: "gone")
                              .group(:runner_id)
                              .pluck(:runner_id, Arel.sql("COUNT(*)"), Arel.sql("COUNT(current_session_id)"))
      by_runner = rows.to_h { |runner_id, total, busy| [ runner_id, Counts.new(busy: busy, total: total) ] }
      ids.to_h { |id| [ id, by_runner.fetch(id) { Counts.new(busy: 0, total: 0) } ] }
    end

    def label(environment)
      environment.display_name.presence || environment.key
    end

    # The reset that settles the machine is the latest `env.reset` the machine
    # has, read under its row lock: the Return to service that put it in
    # `resetting` is the last one to have enqueued one (it did so under the same
    # lock), so a result of an earlier reset can never settle a later attempt.
    def settle_reset!(machine)
      RunnerEnvironment.transaction do
        locked = RunnerEnvironment.where(id: machine.id, state: "resetting").lock.first
        next unless locked

        operation = RunnerOperation.where(runner_environment_id: locked.id, op: "env.reset").order(:sequence).last
        next if operation.nil? || operation.deliverable?

        if operation.completed?
          locked.finish_reset!
        else
          reason = operation.expired? ? "the runner did not answer" : failure_text(operation.result)
          locked.mark_failed!("#{label(locked)} failed to reset on Return to service: #{reason}")
        end
      end
    end
    private_class_method :settle_reset!

    # "<class>: <message>" of an op result that carries an error.
    def failure_text(result)
      error = result&.dig("error") || {}
      [ error["class"], error["message"] ].compact_blank.join(": ").presence || "no reason given"
    end

    def out_of_rotation_reason(machine)
      return "being returned to service" if machine.resetting?

      machine.state_reason.presence || "no reason recorded"
    end
    private_class_method :out_of_rotation_reason

    def max_consecutive_failures
      Settings.runners.max_consecutive_failures.to_i.clamp(1, 1_000)
    end
    private_class_method :max_consecutive_failures

    def take!(session)
      runner = session.runner
      # A savepoint of its own, so a lost race on the hold's unique index
      # leaves a caller's transaction usable for #acquire!'s second look.
      RunnerEnvironment.transaction(requires_new: true) do
        environment = RunnerEnvironment.free.heard.where(runner_id: runner.id).order(:id)
                                       .lock("FOR UPDATE SKIP LOCKED").first
        if environment.nil?
          availability = availability(runner)
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
  end
end
