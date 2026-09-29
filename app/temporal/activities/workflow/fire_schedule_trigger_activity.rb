# frozen_string_literal: true

module Activities
  module Workflow
    # Fires a schedule TriggerBinding: records a schedule.fired event and starts
    # the bound workflow through the trigger engine (honouring subject_policy).
    class FireScheduleTriggerActivity < Base
      def run(input)
        binding = TriggerBinding.find_by(id: input.trigger_binding_id)
        # A schedule that outlived its binding, or fires one that is off or whose
        # workflow was deleted, starts nothing — and a gone binding's schedule goes.
        unless binding&.live?
          ScheduleReconciler.remove(input.trigger_binding_id) if binding.nil?
          return { workflow_run_id: nil, skipped: binding ? "binding off or workflow deleted" : "binding gone" }
        end

        # Recorded as "dispatched": this activity fires the binding itself and
        # Temporal already retries it, so the outbox relay must not re-sweep it.
        # One event per tick: a retried attempt finds the event (and through its
        # dispatch, the run) the first attempt already made.
        event = tick_event(binding)

        run = TriggerEngine.fire_for_binding(binding: binding, event: event, actor: binding.created_by)
        { workflow_run_id: run.try(:id) }
      end

      private

      # A schedule's workflow id is the schedule id plus the tick's time, so it
      # names the tick across every retry of this activity.
      def tick_event(binding)
        tick = Temporalio::Activity::Context.current_or_nil&.info&.workflow_id
        dedup_key = tick && "schedule_tick:#{tick}"
        TriggerEngine.record_event(
          event_type: TriggerBinding::SCHEDULE_EVENT_TYPE,
          source: "schedule_trigger:#{binding.id}",
          subject: binding.id,
          data: { "trigger_binding_id" => binding.id, "fired_at" => Time.current.iso8601 },
          project: binding.project,
          dedup_key: dedup_key,
          relay_state: "dispatched"
        )
      rescue ActiveRecord::RecordNotUnique
        TriggerEvent.find_by!(dedup_key: dedup_key)
      end
    end
  end
end
