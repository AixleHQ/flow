# frozen_string_literal: true

# The skills catalog mirror.
#
# WHY A MIRROR, AND WHY IT IS NOT THE CONNECTOR MIRROR'S TWIN
# The MCP registry hands out an incremental change feed but publishes no
# popularity data, so `connectors` is an authoritative local copy. skills.sh is
# the opposite: it knows exactly how popular every skill is and exposes that
# ranking only behind a Vercel OIDC token we cannot mint, while its reachable
# surface is a search endpoint that refuses queries under two characters. There is
# no public list endpoint at all.
#
# So this table exists to make a DEFAULT VIEW possible — something to browse
# before the user types — while typed queries keep going upstream live, where
# fuzzy search with an `owner` filter works well. That is the inverse of the
# connector design and the reason this mirror is deliberately incomplete: its
# coverage is a function of the sweep's seed queries, not of the registry's size.
#
# THIS TABLE IS DISPOSABLE. Every row is rebuildable by another sweep. Nothing
# references it by foreign key — an installed `Skill` carries its own copy of the
# content, so a catalog row may be rewritten or dropped without touching a project.
#
# `search_vector` is a stored generated column, matching `connectors`: ranking
# quality becomes a migration rather than an application rewrite. Slug and title
# outweigh description, since someone typing "playwright" means the tool.
class CreateCatalogSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_skills do |t|
      t.string :registry_id, null: false  # "owner/repo/slug" — the id skills.sh uses
      t.string :source, null: false       # "owner/repo"
      t.string :slug, null: false
      t.string :title
      t.text :description

      # Upstream's own number, from anonymous skills CLI telemetry. Public data, so
      # it may be displayed — unlike `connectors.install_count`, which aggregates
      # tenant behaviour. Inflated for multi-skill repos: a repo-level install
      # appears to credit every skill in the repo, which is what `bulk_publisher`
      # exists to counterbalance.
      t.integer :installs, default: 0, null: false
      # Ours: how many projects on this deployment installed it.
      t.integer :install_count, default: 0, null: false

      t.boolean :featured, default: false, null: false
      t.boolean :bulk_publisher, default: false, null: false

      # Registry digest from the download endpoint — the only cheap way to notice
      # that a skill changed upstream.
      t.string :content_hash
      t.datetime :registry_synced_at

      t.timestamps
    end

    add_index :catalog_skills, :registry_id, unique: true
    add_index :catalog_skills, :source
    add_index :catalog_skills, %i[featured bulk_publisher installs], name: "index_catalog_skills_on_ranking"
    # `MAX(registry_synced_at)` is read on every Skills page render (the "last synced"
    # line), and the backfill queue orders by it.
    add_index :catalog_skills, :registry_synced_at

    # `reversible`, not a bare `execute`: a raw statement inside `change` makes the
    # whole migration irreversible, so `db:rollback` would raise instead of dropping
    # the release's table.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          ALTER TABLE catalog_skills ADD COLUMN search_vector tsvector
          GENERATED ALWAYS AS (
            setweight(to_tsvector('simple', coalesce(slug, '')), 'A') ||
            setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
            setweight(to_tsvector('simple', coalesce(source, '')), 'B') ||
            setweight(to_tsvector('simple', coalesce(description, '')), 'C')
          ) STORED
        SQL
      end

      dir.down do
        execute "ALTER TABLE catalog_skills DROP COLUMN IF EXISTS search_vector"
      end
    end

    add_index :catalog_skills, :search_vector, using: :gin
  end
end
