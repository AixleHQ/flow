# frozen_string_literal: true

module Runners
  # Whether the platform has heard from a `manual` machine lately
  # (docs/design/agent-runtimes/DESIGN.md §2.2, §2.5, §6.2).
  #
  #   Runners::Liveness.record!(runner_id:, environment_id:)  # every authenticated request of a machine
  #   Runners::Liveness.states(environments)                  # => { id => "online" | "idle" | "offline" | "failed" | "gone" }
  #
  # Every authenticated request of a machine (its polls, op results, check-in,
  # token refresh and registration) records its time in
  # runner_environments.last_heartbeat_at, and the runner's `last_seen_at` is the
  # latest of its machines'. A machine is written at most once per RECORD_EVERY,
  # not on every request.
  #
  # A machine is heard for RunnerEnvironment::ONLINE_WINDOW. The exception is
  # the host runner running one op at a time without polling (§6.7): a machine
  # executing a delivered op is not offline before that op's deadline
  # (RunnerEnvironment.executing_op).
  module Liveness
    RECORD_EVERY = 15.seconds

    ONLINE = "online"
    IDLE = "idle"
    OFFLINE = "offline"

    module_function

    # Records that the machine was heard `now`, unless it was recorded within
    # RECORD_EVERY. Plain writes: neither the environment's nor the runner's
    # `updated_at` moves, since a heartbeat is not a change of either. Answers
    # whether it wrote.
    def record!(runner_id:, environment_id:, now: Time.current)
      written = RunnerEnvironment.where(id: environment_id)
                                 .not_heard_since(now - RECORD_EVERY)
                                 .update_all(last_heartbeat_at: now)
      return false if written.zero?

      Runner.where(id: runner_id).not_seen_since(now).update_all(last_seen_at: now)
      true
    end

    # The display state of each machine (§2.5), by id: `failed` and `gone` as
    # they are, and for a `registered` one `online` (reachable and holding a
    # session), `idle` (reachable, none) or `offline`.
    def states(environments, now: Time.current)
      registered = environments.select { |environment| environment.state == "registered" }
      executing = RunnerEnvironment.executing_op(now).where(id: registered.map(&:id)).pluck(:id).to_set

      environments.to_h do |environment|
        [ environment.id, state_of(environment, executing: executing.include?(environment.id), now: now) ]
      end
    end

    def state_of(environment, executing:, now:)
      return environment.state.to_s unless environment.state == "registered"
      return OFFLINE unless executing || environment.heard?(now)

      environment.current_session_id ? ONLINE : IDLE
    end
    private_class_method :state_of
  end
end
