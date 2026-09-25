# frozen_string_literal: true

class AddBindingCreatedIndexToTriggerDispatches < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :trigger_dispatches, %i[trigger_binding_id created_at],
              name: "index_trigger_dispatches_on_binding_and_created_at",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
