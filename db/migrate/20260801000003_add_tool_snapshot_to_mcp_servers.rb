# frozen_string_literal: true

# Records what an MCP server declared it could do, so a later change is visible.
#
# The catalog installs anything the public registry lists — no allowlist — on
# the grounds that the agent container is already an arbitrary-code-execution
# environment. That trade is only defensible with the compensating controls it
# assumes: pinning the exact version (already emitted) and NOTICING when a
# server's declared tools change after approval. This is the second one.
#
# The threat is a rug pull: ship a benign tool catalogue, get installed, then
# swap in a tool description carrying instructions for the model (OWASP
# MCP03:2025). The protocol has a notification for this, but shipping agents
# demonstrably ignore it, so the platform keeps its own baseline.
#
# `tool_snapshot` holds fingerprints (name + digests), never the descriptions
# themselves — the snapshot answers "did this change?", and keeping a copy of
# attacker-controlled text invites rendering it somewhere later.
class AddToolSnapshotToMCPServers < ActiveRecord::Migration[8.1]
  def change
    add_column :mcp_servers, :tool_snapshot, :jsonb, default: {}, null: false
    add_column :mcp_servers, :tool_snapshot_at, :datetime
    # Populated only when a re-probe disagrees with the snapshot: what changed,
    # and when it was noticed. Cleared when a human accepts the new baseline.
    add_column :mcp_servers, :tool_drift, :jsonb, default: {}, null: false

    # "Which installs need attention?" — small, partial, and the only query the
    # drift surface needs.
    add_index :mcp_servers, :id, where: "tool_drift <> '{}'::jsonb", name: "index_mcp_servers_with_tool_drift"
  end
end
