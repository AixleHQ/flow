# frozen_string_literal: true

# Pods of the release before CreateResourceLinks kept serving while it rolled
# out, and they wrote the jsonb lists without mirroring them. Reads move to the
# links in this release, so every list whose links disagree with it is linked
# again; a list that agrees keeps its rows.
class ResyncResourceLinks < ActiveRecord::Migration[8.1]
  KINDS = {
    tool: :tools, skill: :skills, mcp_server: :mcp_servers,
    asset: :assets, repository: :repositories, config_item: :config_items
  }.freeze

  def up
    KINDS.each do |kind, target|
      resync :step_resource_links, :step_id, target, kind,
             from: "steps", list: "steps.#{kind}_ids"
      resync :workflow_resource_links, :workflow_id, target, kind,
             from: "workflows", list: "workflows.config -> 'base_#{kind}_ids'"
    end
  end

  def down; end

  private

  def resync(table, owner_column, target, kind, from:, list:)
    column = "#{kind}_id"
    wanted = <<~SQL
      SELECT DISTINCT ON (#{from}.id, #{target}.id) #{from}.id AS owner_id, #{target}.id AS resource_id, element.ordinality
      FROM #{from}
      CROSS JOIN LATERAL jsonb_array_elements_text(
        CASE WHEN jsonb_typeof(#{list}) = 'array' THEN #{list} ELSE '[]'::jsonb END
      ) WITH ORDINALITY AS element(value, ordinality)
      JOIN #{target} ON element.value ~ '^[0-9]+$' AND #{target}.id = element.value::bigint
      ORDER BY #{from}.id, #{target}.id, element.ordinality
    SQL

    execute(<<~SQL.squish)
      DELETE FROM #{table} WHERE #{column} IS NOT NULL AND #{owner_column} IN (
        SELECT owner_id
        FROM (SELECT owner_id, array_agg(resource_id ORDER BY ordinality) AS ids
              FROM (#{wanted}) wanted GROUP BY owner_id) wanted
        FULL JOIN (SELECT #{owner_column} AS owner_id, array_agg(#{column} ORDER BY position) AS ids
                   FROM #{table} WHERE #{column} IS NOT NULL GROUP BY #{owner_column}) linked USING (owner_id)
        WHERE wanted.ids IS DISTINCT FROM linked.ids
      )
    SQL

    execute(<<~SQL.squish)
      INSERT INTO #{table} (#{owner_column}, #{column}, position)
      SELECT owner_id, resource_id, ordinality FROM (#{wanted}) wanted
      WHERE NOT EXISTS (
        SELECT 1 FROM #{table} WHERE #{table}.#{owner_column} = wanted.owner_id AND #{table}.#{column} IS NOT NULL
      )
    SQL
  end
end
