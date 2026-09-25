# frozen_string_literal: true

# Version history for workflows, agents, skills, custom tools and MCP servers
# (docs/design/entity-versioning.md). Rows are immutable: one per explicit save,
# revert, archive or restore, each carrying a full snapshot of the entity.
class CreateEntityVersions < ActiveRecord::Migration[8.1]
  VERSIONED = %i[workflows agents skills tools mcp_servers].freeze
  ARCHIVABLE = %i[agents skills mcp_servers].freeze

  def change
    create_table :entity_versions do |t|
      t.string :versionable_type, null: false
      t.bigint :versionable_id, null: false
      t.integer :number, null: false
      t.string :event, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.integer :snapshot_format, null: false, default: 1
      t.references :restored_from, foreign_key: { to_table: :entity_versions, on_delete: :nullify }, index: false
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.string :source, null: false
      t.references :terminal_session, foreign_key: { on_delete: :nullify }, index: { where: "terminal_session_id IS NOT NULL" }
      t.jsonb :metadata, null: false, default: {}
      t.references :project, foreign_key: { on_delete: :cascade }, index: false
      t.references :company, foreign_key: { on_delete: :cascade }, index: false
      t.datetime :created_at, null: false
    end

    add_index :entity_versions, %i[versionable_type versionable_id number], unique: true,
                                                                           name: "index_entity_versions_on_versionable_and_number"
    add_index :entity_versions, %i[project_id created_at]
    add_check_constraint :entity_versions, "number > 0", name: "entity_versions_number_positive"

    VERSIONED.each do |table|
      add_column table, :current_version_number, :integer, null: false, default: 0
    end

    ARCHIVABLE.each do |table|
      add_column table, :archived_at, :datetime
    end

    # A name is unique among the live rows only, as it already is for tools and
    # workflows, so an archived entity does not block reusing its name.
    remove_index :agents, %i[scope_type scope_id name], unique: true,
                                                        name: "index_agents_on_scope_type_and_scope_id_and_name"
    add_index :agents, %i[scope_type scope_id name], unique: true, where: "archived_at IS NULL",
                                                     name: "index_agents_on_scope_type_and_scope_id_and_name"
    remove_index :skills, %i[scope_type scope_id name], unique: true, nulls_not_distinct: true,
                                                        name: "index_skills_on_scope_type_and_scope_id_and_name"
    add_index :skills, %i[scope_type scope_id name], unique: true, nulls_not_distinct: true, where: "archived_at IS NULL",
                                                     name: "index_skills_on_scope_type_and_scope_id_and_name"
    remove_index :mcp_servers, %i[name scope_type scope_id], unique: true, nulls_not_distinct: true,
                                                             name: "index_mcp_servers_on_name_and_scope_type_and_scope_id"
    add_index :mcp_servers, %i[name scope_type scope_id], unique: true, nulls_not_distinct: true, where: "archived_at IS NULL",
                                                          name: "index_mcp_servers_on_name_and_scope_type_and_scope_id"
  end
end
