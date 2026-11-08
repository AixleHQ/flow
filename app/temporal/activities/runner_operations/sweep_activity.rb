# frozen_string_literal: true

module Activities
  module RunnerOperations
    # The runner queue's housekeeping (docs/design/agent-runtimes/DESIGN.md §2.3,
    # §6.4): ops past their deadline that never got a result are expired, and
    # finished ops older than seven days are deleted, each environment's newest
    # kept (Runners::Operations.prune!).
    class SweepActivity < Base
      def run(_input = nil)
        { expired: ::Runners::Operations.expire_overdue!, pruned: ::Runners::Operations.prune! }
      end
    end
  end
end
