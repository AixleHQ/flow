# frozen_string_literal: true

# Code-first tool registry, stage 1: the `tools` table becomes a hybrid of
# reconciler-owned shadow rows for code-defined platform tools (source: "code")
# and user-authored custom tools (source: "db"). See Tools::Reconciler.
class AddSourceToTools < ActiveRecord::Migration[8.1]
  def change
    add_column :tools, :source, :string, null: false, default: "db"
    add_column :tools, :user_attachable, :boolean, null: false, default: true
    add_column :tools, :tags, :jsonb, null: false, default: []

    # Custom tools must never be able to claim the managed-MCP namespace
    # (mcp__<server>__<tool>); enforced at the DB level so even console writes
    # can't shadow a managed tool. NOT VALID: existing rows are reported by
    # tools:check instead of failing the migration.
    add_check_constraint :tools, "name NOT LIKE 'mcp\\_\\_%'",
                         name: "tools_name_not_managed_namespace", validate: false
  end
end
