# frozen_string_literal: true

module Runners
  # The `env.reset` of the machine a stale session still holds
  # (Activities::Session::CleanupStaleActivity#cleanup_runner_session). It runs
  # here and not in the sweep, which is capped by `runners.scan_op_timeout`: the
  # reset gets the lifecycle budget a cleanup after a session gets, and a silent
  # machine holds up this job only. The machine is free when the reset succeeds
  # and `failed` when it fails (Runners::Machines.reset_held!). A machine that
  # was not heard when the reset expired is tried again later: nothing is known
  # of it, and a Revoke ends the wait, since it clears the hold.
  class ResetStaleMachineJob < ApplicationJob
    queue_as :default

    RETRY_AFTER = 5.minutes

    def perform(session_id)
      session = TerminalSession.find_by(id: session_id)
      return unless session&.runner_id

      result = Runners::Machines.reset_held!(session)
      self.class.set(wait: RETRY_AFTER).perform_later(session_id) if result == :unheard
      result
    end
  end
end
