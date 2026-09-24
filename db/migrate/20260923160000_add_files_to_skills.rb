# frozen_string_literal: true

class AddFilesToSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :skills, :files, :jsonb, null: false, default: {}
  end
end
