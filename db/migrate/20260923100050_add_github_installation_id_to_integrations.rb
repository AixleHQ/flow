# frozen_string_literal: true

# A GitHub App installation id gets a column of its own (it is not a secret), so
# the app can ask which company already holds an installation and refuse a second
# claim; until now it lived only inside the encrypted credentials blob.
class AddGithubInstallationIdToIntegrations < ActiveRecord::Migration[8.1]
  def up
    add_column :integrations, :github_installation_id, :bigint
    add_index :integrations, :github_installation_id

    backfill
  end

  def down
    remove_index :integrations, :github_installation_id
    remove_column :integrations, :github_installation_id
  end

  private

  # The application model on purpose: the credentials key is derived from the
  # model's class name (Encryptable), so a migration-local class could not
  # decrypt the rows it is backfilling.
  def backfill
    ::Integration.reset_column_information
    ::Integration.where(provider: "github").find_each do |integration|
      installation_id = integration.credentials_data["installation_id"]
      next if installation_id.blank?

      integration.update_column(:github_installation_id, installation_id.to_i)
    rescue Encryptable::DecryptionError
      # Unusable either way; its owner reconnects it, which records the id.
      say "integration #{integration.id}: credentials unreadable with this server's keys, installation id not backfilled"
    end
  end
end
