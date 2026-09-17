# frozen_string_literal: true

# First-party Flow ↔ Aixle Insights sharing: project opt-in gate plus a
# project-scoped connection token (digest-only). Plaintext is shown once at
# generation and never persisted — same pattern as User MCP tokens.
class AddInsightsSharingToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :share_usage_with_insights, :boolean, default: false, null: false
    add_column :projects, :insights_connection_token_digest, :string
    add_column :projects, :insights_connection_token_last_used_at, :datetime
    add_index :projects, :insights_connection_token_digest, unique: true,
              where: "insights_connection_token_digest IS NOT NULL",
              name: "index_projects_on_insights_connection_token_digest"
  end
end
