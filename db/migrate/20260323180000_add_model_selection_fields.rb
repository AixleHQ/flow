# frozen_string_literal: true

class AddModelSelectionFields < ActiveRecord::Migration[8.1]
  def change
    add_column :terminal_sessions, :requested_model, :string
    add_column :steps, :preferred_model, :string
  end
end
