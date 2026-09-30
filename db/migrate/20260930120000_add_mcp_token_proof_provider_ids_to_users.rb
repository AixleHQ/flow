# frozen_string_literal: true

class AddMCPTokenProofProviderIdsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mcp_token_proof_provider_ids, :bigint, array: true
  end
end
