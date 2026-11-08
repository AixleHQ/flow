# frozen_string_literal: true

module Sessions
  module Checks
    # What a check tells Sessions::Monitor after looking at a session's snapshot.
    #
    # `outcome` names what the check did, for the pass's counts and the tests
    # (:failed, :paused, :resumed, :nudged, :pending, :taken_over), or nil when it did
    # nothing. `stop` says whether the monitor hands the snapshot on to the next check:
    # true once the check has taken the session over (failed it, paused it, typed into
    # it), or found that another path has.
    Result = Data.define(:outcome, :stop) do
      def stop? = stop
    end
  end
end
