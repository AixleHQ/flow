# frozen_string_literal: true

class CreateConfigItems < ActiveRecord::Migration[8.0]
  def change
    create_table :config_items do |t|
      t.string :name, null: false
      t.text :value                    # Plain text for variables
      t.text :encrypted_value          # Encrypted for secrets
      t.text :description
      t.string :item_type, null: false
      t.string :scope_type, null: false  # 'Company' or 'Project'
      t.bigint :scope_id, null: false

      t.timestamps
    end

    # Unique name within scope
    add_index :config_items, %i[scope_type scope_id name], unique: true
    add_index :config_items, %i[scope_type scope_id]
  end
end
