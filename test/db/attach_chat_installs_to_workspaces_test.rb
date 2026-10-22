# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261022120100_attach_chat_installs_to_workspaces")

class AttachChatInstallsToWorkspacesTest < ActiveSupport::TestCase
  def migrate
    migration = AttachChatInstallsToWorkspaces.new
    migration.suppress_messages do
      migration.remove_index :chat_conversations, %i[chat_workspace_id external_id]
      migration.up
    end
  end

  test "every Slack and Teams install gets the workspace it serves, with its channels and endpoint" do
    company = create(:company)
    slack = create(:integration, provider: :slack, status: :active, company: company, settings: { "team_id" => "T1", "team_name" => "Acme" })
    teams = create(:integration, provider: :teams, status: :active, company: company, settings: { "tenant_id" => TEAMS_CUSTOMER_TENANT })
    pending = create(:integration, provider: :teams, status: :inactive, company: company)
    [ slack, teams ].each { |install| install.update_columns(chat_workspace_id: nil) }
    ChatWorkspace.delete_all
    channel = ChatConversation.create!(integration: slack, provider: "slack", external_id: "C0LEGACY01", kind: "channel")
    channel.update_columns(chat_workspace_id: nil)
    endpoint = create(:webhook_endpoint, slug: "slack-team-T1", provider: :slack, company: company,
                                         config: { "integration_id" => slack.id, "team_id" => "T1" })

    migrate

    workspace = slack.reload.chat_workspace
    assert_equal [ "slack", "T1", "Acme" ], [ workspace.provider, workspace.external_id, workspace.name ]
    assert_equal [ "teams", TEAMS_CUSTOMER_TENANT ], [ teams.reload.chat_workspace.provider, teams.chat_workspace.external_id ]
    assert_nil pending.reload.chat_workspace_id
    assert_equal workspace.id, channel.reload.chat_workspace_id
    assert_equal workspace.id, endpoint.reload.config["chat_workspace_id"]
  end
end
