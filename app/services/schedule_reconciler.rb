# frozen_string_literal: true

# Keeps a schedule TriggerBinding in sync with its backing Temporal Schedule.
# Reconcile = delete any existing schedule, then (re)create it from the binding's
# schedule_config — so cron/timezone edits and enable/disable all converge.
# Runs off the request via ScheduleReconcileJob.
class ScheduleReconciler
  class << self
    def reconcile(binding)
      return unless binding&.schedule?

      sid = schedule_id(binding.id)
      TemporalService.delete_binding_schedule(sid)

      return unless binding.enabled

      cron = binding.schedule_config["cron"]
      return if cron.blank?

      TemporalService.create_binding_schedule(
        schedule_id: sid,
        cron: cron,
        timezone: binding.schedule_config["timezone"],
        input: { "trigger_binding_id" => binding.id }
      )
    end

    def remove(binding_id)
      TemporalService.delete_binding_schedule(schedule_id(binding_id))
    end

    def schedule_id(binding_id)
      "schedule-trigger-#{binding_id}"
    end
  end
end
