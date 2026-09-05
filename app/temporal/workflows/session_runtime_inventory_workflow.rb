# frozen_string_literal: true

module Workflows
  # A single short activity, wrapped only so that a process without runtime
  # access can ask a process that has it.
  class SessionRuntimeInventoryWorkflow < Base
    def run(_input = nil)
      execute_activity(activities.session_runtime_inventory_activity, {}, start_to_close_timeout: 60)
    end
  end
end
