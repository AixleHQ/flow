# frozen_string_literal: true

# Reconciles the columns that reached db/schema.rb through a schema dump of a
# hand-modified development database instead of through a migration.
#
# Because development, test and CI databases are all built with
# `db:schema:load`, these existed everywhere except production — where
# `mcp_servers.args` surfaced as an ActiveModel::UnknownAttributeError the first
# time somebody installed a package connector.
#
# Every statement is conditional: the databases that already have these columns
# (any database loaded from schema.rb) must reach the same end state as the ones
# that never did.
#
#   * mcp_servers.args               — kept. Written by MCP::ConnectorAttributes
#                                      and read by every agent adapter.
#   * skills.references_data         — dropped. Nothing ever wrote it; its only
#                                      reader was WorkflowDuplicator, which is
#                                      updated in this change.
#   * usage_statistics.cursor_token_fee_cents — dropped. No reader, no writer.
#   * index_tools_on_scope_type      — dropped. Redundant with the
#                                      (scope_type, scope_id, name) index.
class ReconcileSchemaDriftWithMigrations < ActiveRecord::Migration[8.1]
  def change
    add_column :mcp_servers, :args, :jsonb, default: [], if_not_exists: true

    remove_column :skills, :references_data, :jsonb, default: {}, if_exists: true
    remove_column :usage_statistics, :cursor_token_fee_cents, :decimal,
      precision: 12, scale: 6, default: "0.0", if_exists: true
    remove_index :tools, :scope_type, name: "index_tools_on_scope_type", if_exists: true
  end
end
