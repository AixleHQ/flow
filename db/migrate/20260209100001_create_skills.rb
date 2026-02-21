# frozen_string_literal: true

class CreateSkills < ActiveRecord::Migration[7.2]
  def change
    create_table :skills do |t|
      t.string :name, null: false
      t.string :title
      t.text :content
      t.text :description
      t.string :kind, null: false, default: "custom"
      t.string :scope_type    # nullable for internal
      t.bigint :scope_id      # nullable for internal
      t.timestamps
    end

    add_index :skills, %i[scope_type scope_id name], unique: true
    add_index :skills, %i[scope_type scope_id]
    add_index :skills, :kind
  end
end
