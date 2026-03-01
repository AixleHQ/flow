# frozen_string_literal: true

class AddDefaultAgentCredentialToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :default_agent_credential, foreign_key: { to_table: :agent_credentials }, null: true
  end
end
