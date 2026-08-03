# frozen_string_literal: true

# The connector catalog mirror: a local copy of the Official MCP Registry.
#
# WHY A MIRROR AND NOT A LIVE PROXY
# The registry's own `search` parameter matches SERVER NAME SUBSTRINGS ONLY, so
# proxying it would return nothing for "issue tracker" or "CRM". The registry
# also publishes no uptime or data-durability guarantee and explicitly directs
# consumers to "scrape data on a regular but infrequent basis and persist it in
# their own data store". Searching locally is therefore both the only way to get
# usable search and the vendor-recommended architecture.
#
# THIS TABLE IS DISPOSABLE. The registry is the source of truth; every row is
# rebuildable by a full re-sync. It needs no backup and can be truncated wholesale
# if the registry resets its data during preview. Nothing may hold a foreign key
# to it — see AddConnectorProvenanceToMCPServers for why installs reference
# connectors by name instead.
#
# `search_vector` is a stored generated column so ranking-quality changes are a
# migration rather than an application-layer rewrite. Weights: name and title
# above description, since a user typing "linear" means the product, not any
# server whose prose mentions it.
class CreateConnectors < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors do |t|
      t.string :name, null: false           # registry name, e.g. "io.github.owner/server"
      t.string :version
      t.string :title
      t.text :description
      t.string :repository_url

      # Normalized by MCP::ConnectorManifest — never a raw registry payload.
      t.jsonb :manifest, default: {}, null: false

      # Registry moderation lifecycle: active | deprecated | deleted.
      # Deleted entries are KEPT so existing installs can still resolve their
      # provenance and be warned; they are excluded from discovery instead.
      t.string :status, default: "active", null: false
      t.boolean :is_latest, default: true, null: false

      # Upstream's own timestamp, which drives the incremental `updated_since`
      # sync. Distinct from updated_at, which records when WE last wrote the row.
      t.datetime :registry_updated_at

      t.timestamps
    end

    add_index :connectors, :name, unique: true
    add_index :connectors, :status
    add_index :connectors, :registry_updated_at

    execute <<~SQL.squish
      ALTER TABLE connectors ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        setweight(to_tsvector('simple', coalesce(name, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(description, '')), 'B')
      ) STORED
    SQL

    add_index :connectors, :search_vector, using: :gin
  end
end
