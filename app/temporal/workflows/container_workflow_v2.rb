# frozen_string_literal: true

module Workflows
  # Container workflow for admitted sessions. Same phase sequence as its parent;
  # what changes is that waiting is expressed as workflow time instead of
  # activity failure — for cluster capacity on the way in, and for asynchronous
  # deletion on the way out.
  class ContainerWorkflowV2 < ContainerWorkflow
    CAPACITY_RETRY_INTERVAL = 30
    CLEANUP_RETRY_INTERVAL = 15

    # About five minutes of waiting on Kubernetes to finish a delete. Past that
    # the workflow stops holding its history open: the reservation stays taken
    # (an unconfirmed delete never frees capacity) and the minutely reconciler
    # keeps re-confirming absence until it can release it.
    CLEANUP_RETRY_ATTEMPTS = 20

    # On the cancellation path the workflow is already unwinding, so it gives
    # the delete a short escort and then hands the rest to reconciliation.
    CLEANUP_DETACHED_ATTEMPTS = 4

    private

    def run_phase(phase, error: nil, timeout: 300, retry_policy: nil)
      cleanup_attempts = 0
      loop do
        result = execute_activity(activities.container_admitted_phase_activity,
          { phase: phase, state: @state, error: error, **passthrough_fields },
          start_to_close_timeout: timeout,
          # Retrying is safe: the activity refuses to replay an operation it
          # cannot prove was never dispatched, and adopts by stable identity
          # otherwise. One attempt would turn every hiccup into a lost slot.
          retry_policy: retry_policy || Temporalio::RetryPolicy.new(max_attempts: 3, initial_interval: 2))
        return result unless result.is_a?(Hash)

        if flag(result, "capacity_wait")
          Temporalio::Workflow.sleep(CAPACITY_RETRY_INTERVAL)
          next
        end
        return result unless flag(result, "cleanup_pending")

        cleanup_attempts += 1
        if cleanup_attempts >= CLEANUP_RETRY_ATTEMPTS
          Temporalio::Workflow.logger.warn(
            "[ContainerWorkflowV2] Runtime still present after cleanup; reservation held for reconciliation"
          )
          return result
        end
        Temporalio::Workflow.sleep(CLEANUP_RETRY_INTERVAL)
      end
    end

    def run_cleanup_detached(error_message)
      # Detached from the workflow's own cancellation: this cleanup exists
      # BECAUSE the workflow was cancelled, so it must not be cancelled with it.
      detached = Temporalio::Cancellation.new
      CLEANUP_DETACHED_ATTEMPTS.times do |attempt|
        result = execute_activity(activities.container_admitted_phase_activity,
          { phase: "cleanup", error: error_message, **passthrough_fields },
          start_to_close_timeout: 120,
          retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2, initial_interval: 5),
          cancellation: detached)
        return result unless result.is_a?(Hash) && flag(result, "cleanup_pending")

        Temporalio::Workflow.sleep(CLEANUP_RETRY_INTERVAL, cancellation: detached) if attempt < CLEANUP_DETACHED_ATTEMPTS - 1
      end
      Temporalio::Workflow.logger.warn("[ContainerWorkflowV2] Cleanup on cancel unconfirmed; reservation held for reconciliation")
      nil
    rescue StandardError => e
      Temporalio::Workflow.logger.error("[ContainerWorkflowV2] Cleanup unresolved: #{e.message}")
    end

    # Activity results cross the wire as JSON, so a flag written with a symbol
    # key comes back as a string one.
    def flag(result, key) = result[key] || result[key.to_sym]

    def passthrough_fields
      super.merge(admission_id: @input.admission_id, permit_token: @input.permit_token)
    end
  end
end
