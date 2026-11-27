# frozen_string_literal: true

module Activities
  module RunnerMachines
    # The reset of the machines that a stale session still holds
    # (docs/design/agent-runtimes/DESIGN.md §5.3), once a minute
    # (Runners::Machines.sweep_abandoned!). Usually it finds nothing.
    class SettleAbandonedActivity < Base
      def run(_input = nil)
        ::Runners::Machines.sweep_abandoned!
      end
    end
  end
end
