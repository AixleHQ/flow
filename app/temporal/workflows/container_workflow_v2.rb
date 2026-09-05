# frozen_string_literal: true

module Workflows
  class ContainerWorkflowV2 < ContainerWorkflow
    private

    def run_phase(phase, error: nil, timeout: 300, retry_policy: nil)
      loop do
        result = execute_activity(activities.container_admitted_phase_activity,
          { phase: phase, state: @state, error: error, **passthrough_fields },
          start_to_close_timeout: timeout,
          retry_policy: retry_policy || Temporalio::RetryPolicy.new(max_attempts: 1))
        return result unless result.is_a?(Hash) && (result["capacity_wait"] || result[:capacity_wait])
        Temporalio::Workflow.sleep(30)
      end
    end

    def run_cleanup_detached(error_message)
      execute_activity(activities.container_admitted_phase_activity,
        { phase: "cleanup", error: error_message, **passthrough_fields },
        start_to_close_timeout: 120,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2, initial_interval: 5),
        cancellation: Temporalio::Cancellation.new)
    rescue StandardError => e
      Temporalio::Workflow.logger.error("[ContainerWorkflowV2] Cleanup unresolved: #{e.message}")
    end

    def handle_failure(execution_error, cleanup_error)
      super(execution_error || cleanup_error, cleanup_error)
    end

    def passthrough_fields
      super.merge(admission_id: @input.admission_id, permit_token: @input.permit_token)
    end
  end
end
