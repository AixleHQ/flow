# frozen_string_literal: true

module Workflows
  # Started by a Temporal Schedule for a schedule TriggerBinding. Thin by design:
  # it just runs an activity that emits a schedule.fired event and fires the
  # binding (which applies its subject_policy and starts the workflow run).
  class ScheduledTriggerWorkflow < Base
    def run(input = nil)
      execute_activity(
        activities.workflow_fire_schedule_trigger_activity,
        { trigger_binding_id: input&.trigger_binding_id },
        start_to_close_timeout: 120,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
      )
    end
  end
end
