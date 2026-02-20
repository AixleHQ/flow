# frozen_string_literal: true

class MigrateSessionConfigToJoinTables < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  MIGRATED_KEYS = %w[tool_ids skill_ids mcp_server_ids asset_ids repository_ids agent_id mode initial_prompt].freeze
  BATCH_SIZE = 500

  def up
    existing_tools = Tool.pluck(:id).to_set
    existing_skills = Skill.pluck(:id).to_set
    existing_mcp_servers = MCPServer.pluck(:id).to_set
    existing_assets = Asset.pluck(:id).to_set
    existing_repositories = Repository.pluck(:id).to_set
    existing_agents = Agent.pluck(:id).to_set

    migrated = 0

    TerminalSession.where.not(session_config: {}).in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |session|
        config = session.session_config
        next if config.blank?

        migrate_join_table(session.id, config["tool_ids"], :session_tools, :tool_id, existing_tools)
        migrate_join_table(session.id, config["skill_ids"], :session_skills, :skill_id, existing_skills)
        migrate_join_table(session.id, config["mcp_server_ids"], :session_mcp_servers, :mcp_server_id, existing_mcp_servers)
        migrate_join_table(session.id, config["asset_ids"], :session_input_assets, :asset_id, existing_assets)
        migrate_join_table(session.id, config["repository_ids"], :session_repositories, :repository_id, existing_repositories)

        updates = {}
        if config["agent_id"].present? && existing_agents.include?(config["agent_id"])
          updates[:configured_agent_id] = config["agent_id"]
        end
        updates[:mode] = config["mode"] if config["mode"].present?
        updates[:initial_prompt] = config["initial_prompt"] if config["initial_prompt"].present?

        cleaned_config = config.except(*MIGRATED_KEYS)
        updates[:session_config] = cleaned_config

        session.update_columns(updates) if updates.any?
        migrated += 1
      end
    end

    say "Migrated #{migrated} sessions from JSONB to join tables"
  end

  def down
    TerminalSession.in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |session|
        config = session.session_config || {}

        config["tool_ids"] = session_join_ids(:session_tools, :tool_id, session.id)
        config["skill_ids"] = session_join_ids(:session_skills, :skill_id, session.id)
        config["mcp_server_ids"] = session_join_ids(:session_mcp_servers, :mcp_server_id, session.id)
        config["asset_ids"] = session_join_ids(:session_input_assets, :asset_id, session.id)
        config["repository_ids"] = session_join_ids(:session_repositories, :repository_id, session.id)
        config["agent_id"] = session.read_attribute(:configured_agent_id) if session.read_attribute(:configured_agent_id).present?
        config["mode"] = session.read_attribute(:mode) if session.read_attribute(:mode).present?
        config["initial_prompt"] = session.read_attribute(:initial_prompt) if session.read_attribute(:initial_prompt).present?

        session.update_columns(session_config: config, configured_agent_id: nil, mode: "interactive", initial_prompt: nil)
      end
    end
  end

  private

  def migrate_join_table(session_id, ids, table_name, fk_column, existing_ids)
    return if ids.blank?

    ids.select { |id| existing_ids.include?(id) }.each do |id|
      execute(<<~SQL.squish)
        INSERT INTO #{table_name} (terminal_session_id, #{fk_column})
        VALUES (#{session_id}, #{id})
        ON CONFLICT DO NOTHING
      SQL
    end
  end

  def session_join_ids(table, fk_column, session_id)
    select_values("SELECT #{fk_column} FROM #{table} WHERE terminal_session_id = #{session_id}")
  end
end
