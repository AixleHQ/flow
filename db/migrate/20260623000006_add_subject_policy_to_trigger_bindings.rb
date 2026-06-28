# frozen_string_literal: true

# subject_policy answers "what board task, if any, is a triggered run about?" for
# off-board triggers (schedule / Slack / webhook), whose events have no task by
# nature. none = project-level run (board_task_id nil); existing_task = the event's
# task; create_task = create a card in subject_column (titled from the template)
# and run on it.
class AddSubjectPolicyToTriggerBindings < ActiveRecord::Migration[8.1]
  def change
    add_column :trigger_bindings, :subject_policy, :string, null: false, default: "none"
    add_column :trigger_bindings, :subject_title_template, :string
    add_reference :trigger_bindings, :subject_column,
      foreign_key: { to_table: :board_columns, on_delete: :nullify }, null: true, index: true
  end
end
