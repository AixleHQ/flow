class CreateAgentCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :agent_type, null: false
      t.text :encrypted_config_data, null: false
      t.jsonb :metadata, default: {}
      t.datetime :last_used_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :agent_credentials, [ :user_id, :agent_type ], unique: true
    add_index :agent_credentials, :agent_type
  end
end
