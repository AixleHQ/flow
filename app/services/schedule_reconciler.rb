# frozen_string_literal: true

# Keeps a schedule TriggerBinding in sync with its backing Temporal Schedule.
# Reconcile = update the schedule in place from the binding's schedule_config,
# creating it if it is missing, or delete it when the binding is off — so
# cron/timezone edits and enable/disable all converge without the schedule ever
# being absent in between. Runs inline (synchronously) on binding
# create/update/destroy; #reconcile_all re-runs it for every enabled binding on
# worker boot as the durable backstop.
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
    #
    # Converges both ways: a schedule whose binding is gone, off, or bound to a
    # deleted workflow is removed too — a delete that failed while Temporal was
    # down would otherwise fire forever.
    def reconcile_all
      wanted = []
      TriggerBinding.where(enabled: true, event_type: TriggerBinding::SCHEDULE_EVENT_TYPE)
                    .joins(:workflow).merge(Workflow.active).find_each do |binding|
        wanted << schedule_id(binding.id)
        reconcile(binding)
      rescue StandardError => e
        Rails.logger.error("[ScheduleReconciler] reconcile_all failed for binding #{binding.id}: #{e.message}")
      end
      prune_orphans(keep: wanted)
    end

    def prune_orphans(keep:)
      (TemporalService.binding_schedule_ids - keep).each { |sid| TemporalService.delete_binding_schedule(sid) }
    rescue StandardError => e
      Rails.logger.error("[ScheduleReconciler] pruning orphan schedules failed: #{e.class}: #{e.message}")
    end

    def reconcile(binding)
      return unless binding&.schedule?

      sid = schedule_id(binding.id)
      cron = binding.schedule_config["cron"]
      return TemporalService.delete_binding_schedule(sid) unless binding.live? && cron.present?

      TemporalService.upsert_binding_schedule(
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
