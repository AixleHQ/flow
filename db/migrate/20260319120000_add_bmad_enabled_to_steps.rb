# frozen_string_literal: true

class AddBmadEnabledToSteps < ActiveRecord::Migration[7.2]
  def change
    add_column :steps, :bmad_enabled, :boolean, default: false, null: false
  end
end
