# frozen_string_literal: true

class AddDeletedAtToSubSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :sub_steps, :deleted_at, :datetime
    add_index :sub_steps, :deleted_at
  end
end
