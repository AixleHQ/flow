# frozen_string_literal: true

module Runners
  # Which machine of a runner takes a session, until Runners::Allocator
  # (docs/design/agent-runtimes/DESIGN.md §7.3, §15 task 11) replaces it with
  # affinity, project binding and the scrub escalation: a free registered
  # machine, one session per machine (task 8a, decision 2).
  #
  #   environment = Runners::Machines.acquire!(session)  # raises CapacityError when every machine is busy
  #   Runners::Machines.release!(environment, session)   # after its env.reset succeeded
  #   Runners::Machines.fail!(environment, reason)       # its env.reset failed: out of rotation
  #
  # A machine is held through runner_environments.current_session_id, set
  # under the machine's row lock, so two sessions never take one machine; the
  # session records the machine it ran on in terminal_sessions.runner_environment_id.
  # "Online" is decided by heartbeats with task 12; until then a registered
  # machine counts.
  #
  # A machine whose reset failed is `failed` (§5.2) and held by no session, so
  # nothing that happens to the session, its deletion included, returns it to
  # rotation. Return to service is task 11; until then the machine is brought
  # back by unregistering it and configuring it again.
  module Machines
    # The runner has no machine that can take a session (DESIGN.md §8,
    # `runner_unreachable`): none registered, or every one `failed`.
    class NoMachine < StandardError
      def reason = Resolver::UNREACHABLE
    end

    module_function

    # The machine the session holds, or a free one it takes now. Every machine
    # busy raises ContainerRuntime::CapacityError, which the admitted container
    # workflow answers by waiting (`capacity_wait`); no machine that can take a
    # session raises NoMachine.
    def acquire!(session)
      held = held_by(session)
      return held if held

      runner = session.runner
      RunnerEnvironment.transaction do
        environment = RunnerEnvironment.free.where(runner_id: runner.id).order(:id)
                                       .lock("FOR UPDATE SKIP LOCKED").first
        if environment.nil?
          message = unavailable_message(runner)
          raise NoMachine, message if message

          # Only the machines that can come back are counted: a `failed` one
          # does not by itself.
          busy = RunnerEnvironment.where(runner_id: runner.id, state: "registered").count
          raise ContainerRuntime::CapacityError,
                "Waiting for a free machine on runner \"#{runner.name}\" (#{busy} of #{busy} busy)."
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

    # Frees the machine once the session's `env.reset` succeeded.
    def release!(environment, session)
      RunnerEnvironment.where(id: environment.id, current_session_id: session.id, state: "registered")
                       .update_all(current_session_id: nil, state_reason: nil, updated_at: Time.current)
    end

    # Takes the machine out of rotation: `failed`, held by no session, with the
    # reason for people in state_reason. A machine already gone stays gone.
    def fail!(environment, reason)
      RunnerEnvironment.where(id: environment.id).where.not(state: "gone")
                       .update_all(state: "failed", current_session_id: nil, state_reason: reason.to_s.truncate(255),
                                   updated_at: Time.current)
    end

    def held_by(session)
      RunnerEnvironment.find_by(current_session_id: session.id)
    end

    # Why the runner cannot take a session at all, or nil when it has a
    # registered machine, free or busy. `pick_from` names where another runner
    # is picked, for the message.
    def unavailable_message(runner, pick_from = nil)
      return nil if RunnerEnvironment.exists?(runner_id: runner.id, state: "registered")

      failed = RunnerEnvironment.where(runner_id: runner.id, state: "failed").order(:id).to_a
      return no_machine_message(runner, pick_from) if failed.empty?

      failed_message(runner, failed, pick_from)
    end

    def no_machine_message(runner, pick_from = nil)
      "Runner \"#{runner.name}\" has no machine registered. Register a machine on it, or pick another runner" \
        "#{" #{pick_from}" if pick_from}."
    end

    def failed_message(runner, machines, pick_from = nil)
      listed = machines.map { |machine| "#{machine.display_name.presence || machine.key} (#{machine.state_reason.presence || 'no reason recorded'})" }
      "Runner \"#{runner.name}\" has no machine that can take a session: " \
        "#{machines.one? ? 'its machine failed' : 'every machine failed'}: #{listed.join('; ')}. " \
        "To bring a machine back, run `aixle-runner unregister` on it, then `aixle-runner configure` again, " \
        "or pick another runner#{" #{pick_from}" if pick_from}."
    end
  end
end
