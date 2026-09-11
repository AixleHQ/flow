# frozen_string_literal: true

# Column triggers never recorded who added them, so the Triggers tab could not
# say whose identity a run would use and there was no owner to fall back on.
# TriggerBinding (slack / schedule / webhook / custom event) has carried
# created_by since it was introduced; this brings the column kind in line.
#
# Nullable + on_delete: :nullify on purpose: historical rows have no source of
# truth for a creator (they stay "Unknown"), and deleting a user must not delete
# the triggers they created.
class AddCreatedByToColumnWorkflowBindings < ActiveRecord::Migration[8.1]
  def change
    add_reference :column_workflow_bindings, :created_by,
      foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
