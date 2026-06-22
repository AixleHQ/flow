# frozen_string_literal: true

# Normalized event envelope (CloudEvents-style attribute model) for the unified
# event-driven trigger layer. Every trigger source — column moves, wait
# resolution, manual launches, schedules, Slack, arbitrary webhooks — produces
# a TriggerEvent. Doubles as an audit / replay log.
class CreateTriggerEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :trigger_events do |t|
      t.string :event_type, null: false
      t.string :source
      t.string :subject
      t.jsonb :data, null: false, default: {}
      t.string :dedup_key
      t.datetime :occurred_at

      t.references :project, foreign_key: { on_delete: :nullify }, index: false
      t.references :board_task, foreign_key: { on_delete: :nullify }, index: false

      t.timestamps
    end

    add_index :trigger_events, :event_type
    add_index :trigger_events, %i[project_id event_type]
    add_index :trigger_events, :board_task_id
    add_index :trigger_events, :dedup_key, unique: true,
      where: "dedup_key IS NOT NULL", name: "index_trigger_events_on_dedup_key_unique"
  end
end
