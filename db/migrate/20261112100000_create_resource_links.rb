# frozen_string_literal: true

# A step's resource lists and a workflow's base_* lists are jsonb arrays of ids, so
# deleting a repository (or a skill, MCP server, config item) left its id behind and
# the builder showed it as a bare number. These tables hold the same lists with
# foreign keys, so a deleted resource drops out of every list that named it.
#
# Expand step: the jsonb lists stay the source of truth and Step/Workflow mirror
# every write here; reads move over in a later release, and the lists go after it.
class CreateResourceLinks < ActiveRecord::Migration[8.1]
  KINDS = {
    tool: :tools, skill: :skills, mcp_server: :mcp_servers,
    asset: :assets, repository: :repositories, config_item: :config_items
  }.freeze

  def up
    create_links :step_resource_links, :step, :steps
    create_links :workflow_resource_links, :workflow, :workflows

    KINDS.each do |kind, target|
      backfill :step_resource_links, :step_id, target, kind,
               from: "steps", list: "steps.#{kind}_ids"
      backfill :workflow_resource_links, :workflow_id, target, kind,
               from: "workflows", list: "workflows.config -> 'base_#{kind}_ids'"
    end
  end

  def down
    drop_table :workflow_resource_links
    drop_table :step_resource_links
  end

  private

  def create_links(table, owner, owners)
    create_table table do |t|
      t.references owner, null: false, foreign_key: { to_table: owners, on_delete: :cascade }
      KINDS.each do |kind, target|
        t.references kind, foreign_key: { to_table: target, on_delete: :cascade }, index: false
      end
      t.integer :position, null: false
      t.check_constraint "num_nonnulls(#{KINDS.keys.map { |kind| "#{kind}_id" }.join(', ')}) = 1",
                         name: "#{table}_one_resource"
      KINDS.each_key do |kind|
        t.index [ :"#{owner}_id", :"#{kind}_id" ], unique: true, where: "#{kind}_id IS NOT NULL"
        t.index :"#{kind}_id", where: "#{kind}_id IS NOT NULL"
      end
    end
  end

  # Ids whose row is gone are dropped — the foreign key would refuse them, and
  # they are exactly the stale ids this table exists to get rid of.
  def backfill(table, owner_column, target, kind, from:, list:)
    execute(<<~SQL.squish)
      INSERT INTO #{table} (#{owner_column}, #{kind}_id, position)
      SELECT DISTINCT ON (#{from}.id, #{target}.id) #{from}.id, #{target}.id, element.ordinality
      FROM #{from}
      CROSS JOIN LATERAL jsonb_array_elements_text(
        CASE WHEN jsonb_typeof(#{list}) = 'array' THEN #{list} ELSE '[]'::jsonb END
      ) WITH ORDINALITY AS element(value, ordinality)
      JOIN #{target} ON element.value ~ '^[0-9]+$' AND #{target}.id = element.value::bigint
      ORDER BY #{from}.id, #{target}.id, element.ordinality
    SQL
  end
end
