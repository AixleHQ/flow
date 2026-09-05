# frozen_string_literal: true

# What the container runtime is holding, asked of the process that can see it.
#
# Activation must not proceed while the runtime still carries session resources
# from the legacy launch path: those Pods answer to nobody's reservation, so the
# queue would hand out capacity that is already spent. The check therefore has
# to be able to fail, and "I could not look" has to count as a failure — an
# unreadable runtime must never read as an empty one.
class SessionRuntimeInventory
  class Unavailable < StandardError; end

  WORKFLOW_ID = "session-runtime-inventory"

  def self.fetch
    unless TemporalService.enabled?
      raise Unavailable, "Temporal is disabled, so the runtime inventory cannot be verified"
    end

    result = TemporalService.execute_workflow(
      TemporalWorkflowRegistry.session_runtime_inventory_workflow, {},
      id: WORKFLOW_ID, execution_timeout: 120
    )
    raise Unavailable, "The worker did not return a runtime inventory" if result.nil?

    Array(result["resources"])
  rescue Temporalio::Error => e
    raise Unavailable, "Could not reach the worker to read the runtime inventory: #{e.message}"
  end
end
