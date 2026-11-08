# frozen_string_literal: true

module Runners
  # Which machine of a runner takes a session, until Runners::Allocator
  # (docs/design/agent-runtimes/DESIGN.md §7.3, §15 task 11) replaces it with
  # affinity, project binding and the scrub escalation: a free registered
  # machine, one session per machine (task 8a, decision 2).
  #
  #   environment = Runners::Machines.acquire!(session)            # raises CapacityError when every machine is busy
  #   Runners::Machines.release!(environment, session)             # after its env.reset succeeded
  #   Runners::Machines.fail!(environment, reason, holder: session) # its env.reset failed: out of rotation
  #   Runners::Machines.availability(runner)                       # => Availability, for the launch's checks
  #
  # A machine is held through runner_environments.current_session_id, set
  # under the machine's row lock, so two sessions never take one machine; the
  # session records the machine it ran on in terminal_sessions.runner_environment_id.
  # Runners::Operations.enqueue! checks the hold under the same lock, so a
  # session's op is created only while it holds the machine. "Online" is
  # decided by heartbeats with task 12; until then a registered machine counts.
  #
  # A machine whose reset failed is `failed` (§5.2) and held by no session, so
  # nothing that happens to the session, its deletion included, returns it to
  # rotation. Return to service is task 11; until then the machine is brought
  # back by unregistering it and configuring it again.
  module Machines
    # Whether a runner has a machine that can take a session: `:available`
    # (one registered, free or busy), `:none_registered`, or `:all_failed`,
    # with the failed machines for the message.
    Availability = Data.define(:status, :failed) do
      def available? = status == :available
    end

    # The runner has no machine that can take a session (DESIGN.md §8,
    # `runner_unreachable`): none registered, or every one `failed`.
    class NoMachine < StandardError
      def reason = UNREACHABLE
    end

    UNREACHABLE = "runner_unreachable"

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

    # Frees the machine once the session's `env.reset` succeeded.
    def release!(environment, session)
      RunnerEnvironment.where(id: environment.id, current_session_id: session.id, state: "registered")
                       .update_all(current_session_id: nil, state_reason: nil, updated_at: Time.current)
    end

    # Takes the machine out of rotation: `failed`, held by no session, with the
    # reason for people in state_reason. With a `holder`, only while that
    # session still holds it, as #release! does: a late failure of a session
    # that has since released the machine leaves the next session's hold alone.
    # Without one (a reused refresh token), whoever holds it. A machine already
    # gone stays gone.
    def fail!(environment, reason, holder: nil)
      scope = RunnerEnvironment.where(id: environment.id).where.not(state: "gone")
      scope = scope.where(current_session_id: holder.id) if holder
      scope.update_all(state: "failed", current_session_id: nil, state_reason: reason.to_s.truncate(255),
                       updated_at: Time.current)
    end

    def held_by(session)
      RunnerEnvironment.find_by(current_session_id: session.id)
    end

    def availability(runner)
      return Availability.new(status: :available, failed: []) if RunnerEnvironment.exists?(runner_id: runner.id, state: "registered")

      failed = RunnerEnvironment.where(runner_id: runner.id, state: "failed").order(:id).to_a
      Availability.new(status: failed.empty? ? :none_registered : :all_failed, failed: failed)
    end

    # Why the runner cannot take a session, for a result that is not
    # `:available`. `pick_from` names where another runner is picked.
    def unavailable_message(runner, availability, pick_from = nil)
      elsewhere = pick_from ? " #{pick_from}" : ""
      case availability.status
      when :none_registered
        "Runner \"#{runner.name}\" has no machine registered. Register a machine on it, or pick another runner#{elsewhere}."
      when :all_failed
        machines = availability.failed
        listed = machines.map { |machine| "#{machine.display_name.presence || machine.key} (#{machine.state_reason.presence || 'no reason recorded'})" }
        "Runner \"#{runner.name}\" has no machine that can take a session: " \
          "#{machines.one? ? 'its machine failed' : 'every machine failed'}: #{listed.join('; ')}. " \
          "To bring a machine back, run `aixle-runner unregister` on it, then `aixle-runner configure` again, " \
          "or pick another runner#{elsewhere}."
      else
        raise ArgumentError, "runner \"#{runner.name}\" is available"
      end
    end

    def take!(session)
      runner = session.runner
      # A savepoint of its own, so a lost race on the hold's unique index
      # leaves a caller's transaction usable for #acquire!'s second look.
      RunnerEnvironment.transaction(requires_new: true) do
        environment = RunnerEnvironment.free.where(runner_id: runner.id).order(:id)
                                       .lock("FOR UPDATE SKIP LOCKED").first
        if environment.nil?
          availability = availability(runner)
          raise NoMachine, unavailable_message(runner, availability) unless availability.available?

          # Only the machines that can come back are counted: a `failed` one
          # does not by itself.
          busy = RunnerEnvironment.where(runner_id: runner.id, state: "registered").count
          raise ContainerRuntime::CapacityError,
                "Waiting for a free machine on runner \"#{runner.name}\" (#{busy} of #{busy} busy)."
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
