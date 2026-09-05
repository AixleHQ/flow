# frozen_string_literal: true

class AddNotifyOnFailureToTriggerBindings < ActiveRecord::Migration[8.0]
  def change
    add_column :trigger_bindings, :notify_on_failure, :boolean, default: true, null: false
  end
end
