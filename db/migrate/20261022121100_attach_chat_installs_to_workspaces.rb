# frozen_string_literal: true

# Gives every Slack and Teams install the workspace it serves, and moves the
# channel registry and the endpoints under it. Read from the database as it
# runs; logs counts only.
class AttachChatInstallsToWorkspaces < ActiveRecord::Migration[8.1]
  class MigrationIntegration < ActiveRecord::Base
    self.table_name = "integrations"
  end

  class MigrationWorkspace < ActiveRecord::Base
    self.table_name = "chat_workspaces"
  end

  def up
    attached = 0
    MigrationIntegration.where(provider: %w[slack teams]).find_each do |integration|
      external_id = workspace_id_of(integration)
      next if external_id.blank?

      workspace = MigrationWorkspace.find_or_create_by!(provider: integration.provider, external_id: external_id) do |row|
        row.name = integration.settings.to_h["team_name"].presence || integration.settings.to_h["tenant_domain"]
        row.status = integration.status == "active" ? "active" : "inactive"
      end
      integration.update_columns(chat_workspace_id: workspace.id)
      execute(<<~SQL.squish)
        UPDATE chat_conversations SET chat_workspace_id = #{workspace.id.to_i}
        WHERE integration_id = #{integration.id.to_i} AND chat_workspace_id IS NULL
      SQL
      execute(<<~SQL.squish)
        UPDATE webhook_endpoints
        SET config = COALESCE(config, '{}'::jsonb) || jsonb_build_object('chat_workspace_id', #{workspace.id.to_i})
        WHERE config->>'integration_id' = '#{integration.id.to_i}' AND provider IN ('slack', 'teams')
      SQL
      attached += 1
    end
    add_index :chat_conversations, %i[chat_workspace_id external_id], unique: true
    say "chat installs attached to a workspace: #{attached}, workspaces: #{MigrationWorkspace.count}"
  end

  def down
    remove_index :chat_conversations, %i[chat_workspace_id external_id]
  end

  private

  def workspace_id_of(integration)
    settings = integration.settings.to_h
    integration.provider == "slack" ? settings["team_id"] : settings["tenant_id"]
  end
end
