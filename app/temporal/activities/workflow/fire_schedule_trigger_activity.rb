# frozen_string_literal: true

module Activities
  module Workflow
    # Fires a schedule TriggerBinding: records a schedule.fired event and starts
    # the bound workflow through the trigger engine (honouring subject_policy).
    class FireScheduleTriggerActivity < Base
      def run(input)
        binding = TriggerBinding.find(input.trigger_binding_id)

        # Recorded as "dispatched": this activity fires the binding itself and
        # Temporal already retries it, so the outbox relay must not re-sweep it.
        event = TriggerEngine.record_event(
          event_type: TriggerBinding::SCHEDULE_EVENT_TYPE,
          source: "schedule_trigger:#{binding.id}",
          subject: binding.id,
          data: { "trigger_binding_id" => binding.id, "fired_at" => Time.current.iso8601 },
          project: binding.project,
          relay_state: "dispatched"
        )

        run = TriggerEngine.fire_for_binding(binding: binding, event: event, actor: binding.created_by)
        { workflow_run_id: run.try(:id) }
      end
    end
  end
end
