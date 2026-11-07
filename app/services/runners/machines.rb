# frozen_string_literal: true

module Runners
  # Which machine of a runner takes a session, until Runners::Allocator
  # (docs/design/agent-runtimes/DESIGN.md §7.3, §15 task 11) replaces it with
  # affinity, project binding and the scrub escalation: a free registered
  # machine, one session per machine (task 8a, decision 2).
  #
  #   environment = Runners::Machines.acquire!(session)  # raises CapacityError when every machine is busy
  #   Runners::Machines.release!(environment, session)   # after its env.reset succeeded
  #
  # A machine is held through runner_environments.current_session_id, set
  # under the machine's row lock, so two sessions never take one machine; the
  # session records the machine it ran on in terminal_sessions.runner_environment_id.
  # "Online" is decided by heartbeats with task 12; until then a registered
  # machine counts.
  module Machines
    # The runner has no registered machine (DESIGN.md §8, `runner_unreachable`).
    class NoMachine < StandardError
      def reason = Resolver::UNREACHABLE
    end

    # Starts the reason of a machine held after its reset failed.
    RESET_FAILED = "env.reset failed"

    module_function

    # The machine the session holds, or a free one it takes now. Every machine
    # busy raises ContainerRuntime::CapacityError, which the admitted container
    # workflow answers by waiting (`capacity_wait`); no machine at all raises
    # NoMachine.
    def acquire!(session)
      held = held_by(session)
      return held if held

      runner = session.runner
      RunnerEnvironment.transaction do
        environment = RunnerEnvironment.free.where(runner_id: runner.id).order(:id)
                                       .lock("FOR UPDATE SKIP LOCKED").first
        if environment.nil?
          registered = RunnerEnvironment.where(runner_id: runner.id, state: "registered").count
          raise NoMachine, no_machine_message(runner) if registered.zero?

          raise ContainerRuntime::CapacityError,
                "Waiting for a free machine on runner \"#{runner.name}\" (#{registered} of #{registered} busy)."
        end

        environment.update!(current_session: session)
        # Saved on a copy, so the caller's session (a strategy's, with changes
        # of its own) saves nothing else here.
        TerminalSession.find(session.id).update!(runner_environment: environment)
        session.runner_environment_id = environment.id
        session.clear_attribute_changes([ :runner_environment_id ])
        environment
      end
    end

    # Frees the machine once the session's `env.reset` succeeded. A machine
    # whose reset failed is not released: it keeps the session and the reason,
    # and takes no other session.
    def release!(environment, session)
      RunnerEnvironment.where(id: environment.id, current_session_id: session.id)
                       .update_all(current_session_id: nil, state_reason: nil, updated_at: Time.current)
    end

    # Keeps the machine out of rotation with the reason its reset failed.
    def hold_failed!(environment, session, reason)
      RunnerEnvironment.where(id: environment.id, current_session_id: session.id)
                       .update_all(state_reason: "#{RESET_FAILED}: #{reason}".truncate(255), updated_at: Time.current)
    end

    def reset_failed?(environment)
      environment.state_reason.to_s.start_with?(RESET_FAILED)
    end

    def held_by(session)
      RunnerEnvironment.find_by(current_session_id: session.id)
    end

    def registered?(runner)
      RunnerEnvironment.exists?(runner_id: runner.id, state: "registered")
    end

    def no_machine_message(runner, pick_from = nil)
      "Runner \"#{runner.name}\" has no machine registered. Register a machine on it, or pick another runner" \
        "#{" #{pick_from}" if pick_from}."
    end
  end
end
