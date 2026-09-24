# frozen_string_literal: true

class AddStateCreatedIndexToToolResults < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :tool_results, %i[state created_at],
              name: "index_tool_results_on_state_and_created_at",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
