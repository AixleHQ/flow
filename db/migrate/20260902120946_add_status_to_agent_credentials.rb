class AddStatusToAgentCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_credentials, :status, :string, default: "active", null: false
    add_column :agent_credentials, :refresh_error, :string
    add_column :agent_credentials, :refresh_failure_count, :integer, default: 0, null: false
    add_index :agent_credentials, [ :status, :expires_at ]
  end
end
