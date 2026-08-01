# frozen_string_literal: true

# Ranking signals for the catalog's default view.
#
# The Official MCP Registry publishes NO popularity data — no installs, no
# ratings, no downloads. It is a metadata registry, deliberately. So "popular"
# cannot be imported; it has to be something this platform actually knows.
#
# `install_count` is how many MCP servers across the platform were installed
# from this connector. It is refreshed by the catalog sync and used for ORDERING
# ONLY — never displayed — because an exact per-connector figure aggregated
# across every company is tenant usage data that the catalog has no business
# publishing.
#
# `featured` carries a small curated list (Connector::FEATURED) so a cold
# catalog, where every count is zero, still opens on connectors worth seeing
# rather than on whatever the registry happened to touch most recently.
class AddRankingToConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :connectors, :install_count, :integer, default: 0, null: false
    add_column :connectors, :featured, :boolean, default: false, null: false

    # The default catalog view's exact ordering.
    add_index :connectors, [ :install_count, :featured, :registry_updated_at ], name: "index_connectors_on_ranking"
  end
end
