# frozen_string_literal: true

class AddPurposeToRepositories < ActiveRecord::Migration[8.0]
  def change
    add_column :repositories, :purpose, :text
  end
end
