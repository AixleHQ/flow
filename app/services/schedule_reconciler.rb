# frozen_string_literal: true

# Keeps a schedule TriggerBinding in sync with its backing Temporal Schedule.
# Reconcile = delete any existing schedule, then (re)create it from the binding's
# schedule_config — so cron/timezone edits and enable/disable all converge.
# Runs inline (synchronously) on binding create/update/destroy; #reconcile_all
# re-runs it for every enabled binding on worker boot as the durable backstop.
class ScheduleReconciler
  # Prefix for the Temporal schedule id backing a per-binding schedule trigger.
  # TemporalService#delete_schedules keys off this to leave these dynamic
  # schedules alone when it (re)syncs the static schedules.yml set.
  SCHEDULE_ID_PREFIX = "schedule-trigger-"

  class << self
    # (Re)create the Temporal schedule for every enabled schedule binding. Called
    # on worker boot (TemporalService#sync_schedules) so per-binding schedules
    # survive a worker redeploy — otherwise the boot-time static-schedule sync
    # wipes them and nothing else recreates them.
    def reconcile_all
      TriggerBinding.where(enabled: true).find_each do |binding|
        reconcile(binding) if binding.schedule?
      rescue StandardError => e
        Rails.logger.error("[ScheduleReconciler] reconcile_all failed for binding #{binding.id}: #{e.message}")
      end
    end

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
      "#{SCHEDULE_ID_PREFIX}#{binding_id}"
    end
  end
end
