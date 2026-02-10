# frozen_string_literal: true

require "rubygems/package"
require "shellwords"
require "stringio"

# SessionContextService
# Injects session configuration into agent containers.
# Reads from TerminalSession#session_config:
#   - Config files (Story 9.2)
#   - Environment variables with secret resolution (Story 9.3)
#   - MCP server configurations per CLI format (Story 9.4)
#   - Skill files per CLI format (Story 9.6)
#   - Context file with MCP/tool descriptions and agent persona (Story 9.7)
class SessionContextService
  class << self
    # == Story 9.8: Unified Session Context Assembly ==

    # Orchestrate all session context injection steps in correct order.
    # Single entry point for AgentSessionStrategy#before_exec.
    #
    # @param container_id [String] Container identifier
    # @param session [TerminalSession] Session record
    # @param credential [AgentCredential, nil] Optional credential to inject
    def assemble_session_context(container_id, session, credential: nil)
      # Step 1: Credentials (optional)
      if credential.present?
        measure_step("credentials") do
          credential.write_to_container(container_id)
        end
      end

      # Step 2: Config files
      measure_step("config_files") { inject_config_files(container_id, session) }

      # Step 3: MCP config
      measure_step("mcp_config") { inject_mcp_config(container_id, session) }

      # Step 4: Skills
      measure_step("skills") { inject_skills(container_id, session) }

      # Step 5: Context file (after skills — append to same file for Gemini)
      measure_step("context_file") { inject_context_file(container_id, session) }

      Rails.logger.info("[SessionContext] Assembly complete for session #{session.id}")
    end

    # == Story 9.2: Config File Injection ==

    # Inject config files from session_config into container.
    # Expands ~ to agent home directory, creates parent dirs, sets ownership.
    def inject_config_files(container_id, session)
      files = session.config_files
      return if files.blank?

      adapter = adapter_for(session)

      files.each do |path, content|
        expanded = expand_path(path, adapter.home_dir)
        write_file(container_id, expanded, content, adapter.tmpfs_uid)
        Rails.logger.info("[SessionContext] Injected config file: #{path} (#{content.bytesize} bytes)")
      end
    end

    # == Story 9.3: Environment Variable Resolution ==

    # Resolve env vars from session_config, replacing config_item:NAME references
    # with decrypted values from ConfigItem.
    # @return [Hash] resolved { "KEY" => "value" } pairs
    def resolve_env_vars(session)
      vars = session.env_vars
      return {} if vars.blank?

      effective_items = resolve_effective_config_items(session)
      resolved = {}

      vars.each do |key, value|
        resolved_value = resolve_config_item_reference(value, effective_items)
        resolved[key] = resolved_value if resolved_value.present?
      end

      if resolved.any?
        Rails.logger.info("[SessionContext] Resolved env vars: #{resolved.keys.join(', ')} (#{resolved.size} vars)")
      end

      resolved
    end

    # == Story 9.6: Skill Injection ==

    # Inject skill files into container based on session_config["skill_ids"].
    # Each CLI has different skill format and path (adapter.skill_files).
    # Handles append strategy for Gemini (skills appended to GEMINI.md).
    def inject_skills(container_id, session)
      skills = resolve_skills(session)
      return if skills.empty?

      adapter = adapter_for(session)
      files = adapter.skill_files(skills)
      return if files.blank?

      files.each do |path, content|
        expanded = expand_path(path, adapter.home_dir)

        if adapter.skill_merge_strategy == :append
          existing = read_file(container_id, expanded) || ""
          write_file(container_id, expanded, existing + content, adapter.tmpfs_uid)
        else
          write_file(container_id, expanded, content, adapter.tmpfs_uid)
        end

        Rails.logger.info("[SessionContext] Injected skill: #{path} (#{content.bytesize} bytes)")
      end
    end

    # == Story 9.7: Context File Injection ==

    # Generate and inject CLI-specific context file with agent persona,
    # MCP server descriptions, and tool descriptions.
    # Appends to existing content (from config_files or skills injection).
    def inject_context_file(container_id, session)
      content = build_context_content(session)
      return if content.blank?

      adapter = adapter_for(session)
      path = adapter.context_file_path
      return if path.blank?

      expanded = expand_path(path, adapter.home_dir)
      existing = read_file(container_id, expanded) || ""

      separator = existing.present? ? "\n\n---\n\n" : ""
      final_content = existing + separator + content

      write_file(container_id, expanded, final_content, adapter.tmpfs_uid)
      Rails.logger.info("[SessionContext] Injected context file: #{path} (#{content.bytesize} bytes added)")
    end

    # == Story 9.4: MCP Config Injection ==

    # Generate and inject MCP server config files into container.
    # Always includes internal Palad MCP + external servers from session_config.
    # Delegates format generation to adapter, handles merge strategy.
    def inject_mcp_config(container_id, session)
      all_servers = build_all_servers(session)
      return if all_servers.empty?

      adapter = adapter_for(session)
      config_files = adapter.mcp_config(all_servers)
      return if config_files.blank?

      config_files.each do |path, content|
        expanded = expand_path(path, adapter.home_dir)
        write_mcp_file(container_id, expanded, content, adapter.mcp_merge_strategy, adapter.tmpfs_uid)
        Rails.logger.info("[SessionContext] Injected MCP config: #{path} (#{adapter.mcp_merge_strategy})")
      end
    end

    # Generate MCP config content (without injecting).
    # @return [Hash] { path => content } mapping
    def generate_mcp_config(session)
      all_servers = build_all_servers(session)
      return {} if all_servers.empty?

      adapter = adapter_for(session)
      adapter.mcp_config(all_servers)
    end

    private

    # == Timing ==

    def measure_step(name)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
      Rails.logger.info("[SessionContext] Step '#{name}' completed in #{elapsed}ms")
    end

    # == Shared Helpers ==

    def adapter_for(session)
      AgentCredentialsService.for(session.agent_type).adapter
    end

    def expand_path(path, home_dir)
      path.sub(/\A~/, home_dir)
    end

    def resolve_effective_config_items(session)
      return {} unless session.project.present?

      ConfigItem.effective_for_project(session.project)
    end

    # Resolve full config_item:NAME reference (for env vars where entire value is a ref)
    def resolve_config_item_reference(value, effective_items)
      return value unless value.to_s.start_with?("config_item:")

      item_name = value.sub("config_item:", "")
      resolved = effective_items[item_name]

      unless resolved
        Rails.logger.warn("[SessionContext] ConfigItem '#{item_name}' not found, skipping")
        return nil
      end

      resolved
    end

    # Resolve embedded config_item:NAME references (for headers like "Bearer config_item:KEY")
    def resolve_embedded_references(value, effective_items)
      return value unless value.is_a?(String) && value.include?("config_item:")

      value.gsub(/config_item:(\w+)/) do
        item_name = ::Regexp.last_match(1)
        resolved = effective_items[item_name]
        unless resolved
          Rails.logger.warn("[SessionContext] ConfigItem '#{item_name}' not found in header")
          next "config_item:#{item_name}"
        end
        resolved
      end
    end

    # == Context Content Builders (Story 9.7) ==

    def build_context_content(session)
      sections = []

      persona = build_agent_persona(session)
      sections << persona if persona.present?

      mcp = build_mcp_descriptions(session)
      sections << mcp if mcp.present?

      tools = build_tool_descriptions(session)
      sections << tools if tools.present?

      sections.join("\n\n")
    end

    def build_agent_persona(session)
      agent_id = session.configured_agent_id
      return "" if agent_id.blank?

      agent = Agent.find_by(id: agent_id)
      return "" unless agent

      agent.to_system_prompt
    end

    def build_mcp_descriptions(session)
      servers = resolve_mcp_servers_for_descriptions(session)
      return "" if servers.empty?

      lines = [ "## Available MCP Servers\n" ]
      servers.each do |server|
        lines << "### #{server[:name]}"
        lines << server[:display_name] if server[:display_name].present?
        lines << server[:description] if server[:description].present?
        lines << ""
      end
      lines.join("\n")
    end

    def build_tool_descriptions(session)
      tools = session.available_tools.to_a
      return "" if tools.empty?

      lines = [ "## Available Tools\n" ]
      tools.each do |tool|
        lines << "### #{tool.name}"
        desc = [ tool.display_name, tool.description ].compact.join(" — ")
        lines << desc if desc.present?
        if tool.input_schema.present? && tool.input_schema["properties"].present?
          params = tool.input_schema["properties"].map { |k, v| "#{k} (#{v['type']})" }.join(", ")
          lines << "Parameters: #{params}" if params.present?
        end
        lines << ""
      end
      lines.join("\n")
    end

    # Resolve MCP server descriptions: palad-tools (always) + external MCPServer records
    def resolve_mcp_servers_for_descriptions(session)
      result = []

      # Always include palad-tools
      result << {
        name: "palad-tools",
        display_name: nil,
        description: "Internal tools server. Provides project-specific tools configured for this session.\n" \
                     "Call tools via MCP — use `tools/list` to see available tools."
      }

      # Resolve external MCP servers from session config
      ids = session.mcp_server_ids
      if ids.present?
        MCPServer.where(id: ids, enabled: true).find_each do |server|
          result << {
            name: server.name,
            display_name: server.display_name,
            description: server.description
          }
        end
      end

      result
    end

    # == Skill Resolution ==

    def resolve_skills(session)
      ids = session.skill_ids
      return [] if ids.blank?

      skills = Skill.where(id: ids).to_a
      found_ids = skills.map(&:id)
      missing = ids - found_ids

      missing.each { |id| Rails.logger.warn("[SessionContext] Skill #{id} not found, skipping") }
      skills
    end

    # == Container File Operations ==

    def write_file(container_id, path, content, uid = 1001)
      return if path.blank?

      ok = runtime.copy_to(container_id, path, content)
      return unless ok

      owner = uid.to_i
      safe_path = Shellwords.escape(path.to_s)
      cmd = [ "sh", "-c", "chown #{owner}:#{owner} #{safe_path}" ]
      runtime.exec(container_id, cmd)
    end

    def read_file(container_id, path)
      return nil if path.blank?

      tar_data = runtime.copy_from(container_id, path)
      return nil if tar_data.blank?

      extract_file_from_tar(tar_data, path)
    rescue StandardError
      nil
    end

    def extract_file_from_tar(tar_data, path)
      normalized = path.to_s.sub(%r{\A/}, "")
      return nil if normalized.blank?

      reader = Gem::Package::TarReader.new(StringIO.new(tar_data))
      contents = nil

      reader.each do |entry|
        entry_name = entry.full_name.sub(%r{\A\./}, "")
        if entry_name == normalized
          contents = entry.read
          break
        end
      end
      contents
    ensure
      reader&.close
    end

    # == MCP Server Resolution ==

    # Combine internal Palad MCP + resolved external servers
    def build_all_servers(session)
      effective_items = resolve_effective_config_items(session)
      external = resolve_mcp_servers(session).map { |s| resolve_server_headers(s, effective_items) }

      [ build_internal_mcp(session) ] + external
    end

    # Build internal Palad MCP server entry (always included in session containers)
    def build_internal_mcp(session)
      OpenStruct.new(
        name: "palad-tools",
        url: ENV.fetch("MCP_SERVER_URL", "http://web:3000/action_mcp"),
        transport: "sse",
        headers: { "X-Session-Key" => session.mcp_key }
      )
    end

    def resolve_mcp_servers(session)
      ids = session.mcp_server_ids
      return [] if ids.blank?

      servers = MCPServer.where(id: ids, enabled: true).to_a
      found_ids = servers.map(&:id)
      missing = ids - found_ids

      missing.each { |id| Rails.logger.warn("[SessionContext] MCPServer #{id} not found or disabled, skipping") }
      servers
    end

    def resolve_server_headers(server, effective_items)
      resolved_headers = (server.headers || {}).transform_values do |value|
        resolve_embedded_references(value, effective_items)
      end

      OpenStruct.new(
        name: server.name,
        url: server.url,
        transport: server.transport.to_s,
        headers: resolved_headers
      )
    end

    # Write MCP config file respecting merge strategy
    def write_mcp_file(container_id, path, content, strategy, uid)
      case strategy
      when :merge_json
        existing_content = read_file(container_id, path)
        existing = existing_content.present? ? JSON.parse(existing_content) : {}
        new_data = JSON.parse(content)
        merged = existing.merge(new_data)
        write_file(container_id, path, merged.to_json, uid)
      when :append_toml
        existing = read_file(container_id, path) || ""
        write_file(container_id, path, "#{existing}\n\n#{content}", uid)
      else # :fresh
        write_file(container_id, path, content, uid)
      end
    rescue JSON::ParserError => e
      Rails.logger.warn("[SessionContext] Failed to parse existing file #{path}: #{e.message}, writing fresh")
      write_file(container_id, path, content, uid)
    end

    def runtime
      @runtime ||= ContainerRuntime.build
    end
  end
end
