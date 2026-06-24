# frozen_string_literal: true

# schedule_config holds the timing spec for a schedule trigger
# (event_type "schedule.fired"): { "cron" => "0 9 * * 1-5", "timezone" => "UTC" }.
# Each such binding is reconciled onto a Temporal Schedule that fires the
# ScheduledTriggerWorkflow, which emits a schedule.fired event for the binding.
class AddScheduleConfigToTriggerBindings < ActiveRecord::Migration[8.1]
  def change
    add_column :trigger_bindings, :schedule_config, :jsonb, null: false, default: {}
  end
end
