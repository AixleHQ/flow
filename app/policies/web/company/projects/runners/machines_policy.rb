# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Runners
        # A machine of a project's own runner: the policy that guards the
        # runner's update and revoke (docs/design/agent-runtimes/DESIGN.md §3.2).
        class MachinesPolicy < Web::Company::Projects::RunnersPolicy
          # Return to service: a failed machine is reset and rejoins the rotation.
          def return_to_service? = update?
        end
      end
    end
  end
end
