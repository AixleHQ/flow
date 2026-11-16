# frozen_string_literal: true

module Activities
  module RunnerHealth
    # The runners' health check (docs/design/agent-runtimes/DESIGN.md §2.5):
    # every live runner's status from its machines' health, once a minute
    # (Runners::HealthCheck).
    class CheckActivity < Base
      def run(_input = nil)
        ::Runners::HealthCheck.run!
      end
    end
  end
end
