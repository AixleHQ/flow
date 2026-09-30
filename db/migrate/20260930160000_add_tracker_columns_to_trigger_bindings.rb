# frozen_string_literal: true

class AddTrackerColumnsToTriggerBindings < ActiveRecord::Migration[8.1]
  def change
    # RESTRICT, not nullify: nulling would silently widen "this tracker" into
    # "any tracker in the project". Trackers are detached, never deleted, while
    # a binding names them.
    add_reference :trigger_bindings, :project_tracker, foreign_key: { on_delete: :restrict }
    add_column :trigger_bindings, :aixle_changes, :string, null: false, default: "ignore"
  end
end
