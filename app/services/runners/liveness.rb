# frozen_string_literal: true

module Runners
  # Whether the platform has heard from a `manual` machine lately
  # (docs/design/agent-runtimes/DESIGN.md §2.2, §2.5, §6.2).
  #
  #   Runners::Liveness.record!(runner_id:, environment_id:)  # every authenticated request of a machine
  #
  # Every authenticated request of a machine (its polls, op results, check-in,
  # token refresh and registration) records its time in
  # runner_environments.last_heartbeat_at, and the runner's `last_seen_at` is the
  # latest of its machines'. A machine is written at most once per RECORD_EVERY,
  # not on every request.
  #
  # What a machine shows as (online / idle / offline) is RunnerEnvironment#display_state.
  module Liveness
    RECORD_EVERY = 15.seconds

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
  end
end
