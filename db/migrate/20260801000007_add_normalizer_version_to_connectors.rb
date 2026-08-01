# frozen_string_literal: true

# Which build of the normalizer produced each mirrored manifest.
#
# MCP::ConnectorManifest's output is PERSISTED, not computed on read — the
# catalog, the install form and the snapshot all consume the normalized shape.
# That makes the normalizer a schema: changing it leaves every mirrored row
# describing the world as it looked under the old rules, and nothing notices.
#
# It already bit once. Marking the deprecated SSE transport uninstallable had no
# effect on the catalog, because every mirrored manifest had been normalized
# while SSE was still offered. Recording the version turns that silent staleness
# into something the sync can detect and repair on its own.
class AddNormalizerVersionToConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :connectors, :normalizer_version, :string
    add_index :connectors, :normalizer_version
  end
end
