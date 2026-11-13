# frozen_string_literal: true

# Resource lists are step_resource_links and workflow_resource_links now, so
# their jsonb copies go. Dropped in the release that stops writing them: until
# the previous release's pods have rolled, their step inserts and list edits
# fail on the missing columns — a window of minutes, accepted over a release
# of ignored_columns.
class RemoveResourceIdLists < ActiveRecord::Migration[8.1]
  KINDS = %w[tool skill mcp_server asset repository config_item].freeze

  def up
    KINDS.each { |kind| remove_column :steps, "#{kind}_ids" }
    keys = KINDS.map { |kind| "'base_#{kind}_ids'" }.join(", ")
    execute "UPDATE workflows SET config = config - ARRAY[#{keys}] WHERE config ?| ARRAY[#{keys}]"
  end

  def down
    KINDS.each do |kind|
      add_column :steps, "#{kind}_ids", :jsonb, default: [], null: false
      execute <<~SQL.squish
        UPDATE steps SET #{kind}_ids = links.ids
        FROM (#{linked_ids(:step_resource_links, :step_id, kind)}) links WHERE steps.id = links.owner_id
      SQL
      execute <<~SQL.squish
        UPDATE workflows SET config = config || jsonb_build_object('base_#{kind}_ids', links.ids)
        FROM (#{linked_ids(:workflow_resource_links, :workflow_id, kind)}) links WHERE workflows.id = links.owner_id
      SQL
    end
  end

  private

  def linked_ids(table, owner_column, kind)
    "SELECT #{owner_column} AS owner_id, jsonb_agg(#{kind}_id ORDER BY position) AS ids " \
      "FROM #{table} WHERE #{kind}_id IS NOT NULL GROUP BY #{owner_column}"
  end
end
