# frozen_string_literal: true

# Provenance for MCP servers installed from the public connector catalog.
#
# Nullable on purpose: a hand-authored server leaves all three null and behaves
# exactly as before. The catalog is additive — one table, optional provenance —
# so nothing downstream (SessionConfigResolver, the agent adapters, policies)
# has to learn a second kind of row.
#
# `connector_name` is a plain string, NOT a foreign key to the catalog mirror.
# Mirrored catalog rows legitimately disappear: the registry flips a server's
# status to "deleted" on a moderation violation and instructs consumers to drop
# it from their index. An install must outlive its catalog entry, so a real FK
# would either block that cleanup or cascade-delete working user configuration.
#
# `connector_manifest` snapshots the normalized manifest as it was at install
# time — input DECLARATIONS only, never the user's supplied values, which live
# in the existing encrypted headers/env columns. The snapshot is what later
# drift detection diffs against.
class AddConnectorProvenanceToMCPServers < ActiveRecord::Migration[8.1]
  def change
    add_column :mcp_servers, :connector_name, :string
    add_column :mcp_servers, :connector_version, :string
    add_column :mcp_servers, :connector_manifest, :jsonb, default: {}, null: false

    # Answers "which projects installed this connector?" — needed to warn
    # existing installs when a connector is deprecated or deleted upstream.
    add_index :mcp_servers, :connector_name
  end
end
