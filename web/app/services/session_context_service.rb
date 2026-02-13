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
      # Resolve MCP server names early — needed for pre-approving servers
      # in the credential config (e.g. Claude Code's enabledMcpjsonServers)
      mcp_server_names = build_all_servers(session).map(&:name)
      Rails.logger.info("[SessionContext] Pre-resolved MCP server names: #{mcp_server_names.inspect}")

      # Step 1: Credentials (optional)
      if credential.present?
        measure_step("credentials") do
          workflow_config = { enabled_mcp_servers: mcp_server_names }
          Rails.logger.info("[SessionContext] Writing credentials with workflow_config: #{workflow_config.inspect}")
          credential.write_to_container(container_id, workflow_config)
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
    # MCP server descriptions, tool descriptions, and optionally skills.
    #
    # When adapter#includes_skills_in_context? is true, the content is a complete
    # standalone file (e.g. AGENTS.md) — written fresh.
    # Otherwise appends to existing content (for adapters where skills are separate files).
    def inject_context_file(container_id, session)
      content = build_context_content(session)
      return if content.blank?

      adapter = adapter_for(session)
      path = adapter.context_file_path
      return if path.blank?

      expanded = expand_path(path, adapter.home_dir)

      # Write fresh — context file is always generated as a complete document
      write_file(container_id, expanded, content, adapter.tmpfs_uid)

      Rails.logger.info("[SessionContext] Injected context file: #{path} (#{content.bytesize} bytes)")
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
      adapter = adapter_for(session)
      sections = []

      sections << "# Agent Instructions"

      # Section 1: Role / Persona
      persona = build_agent_persona(session)
      sections << persona if persona.present?

      # Section 2: Session context
      sections << build_session_context(session)

      # Section 3: Available MCP servers
      mcp = build_mcp_descriptions(session)
      sections << mcp if mcp.present?

      # Section 4: Available tools
      tools = build_tool_descriptions(session)
      sections << tools if tools.present?

      # Section 5: Skills (when adapter embeds them into context file)
      if adapter.includes_skills_in_context?
        skills_section = build_skills_section(session)
        sections << skills_section if skills_section.present?
      end

      # Section 6: General instructions
      sections << build_general_instructions(session)

      # Section 7: Workflow instructions (placeholder for future use)
      # When workflow steps are implemented, they will be injected here:
      # sections << build_workflow_instructions(session)

      sections.join("\n\n")
    end

    def build_agent_persona(session)
      agent_id = session.configured_agent_id
      return nil if agent_id.blank?

      agent = Agent.find_by(id: agent_id)
      return nil unless agent

      lines = [ "## Your Role" ]
      lines << agent.to_system_prompt
      lines.join("\n\n")
    end

    def build_session_context(session)
      lines = [ "## Session Context" ]
      lines << ""
      lines << "You are running in a standalone #{session.mode} agent session on the Palad platform."
      lines << ""
      lines << "- **Session ID:** #{session.id}"
      lines << "- **Agent Runtime:** #{session.agent_type}"
      lines << "- **Mode:** #{session.mode}"
      lines << "- **Project:** #{session.project.name}" if session.project.present?

      lang = session.user&.preferred_agent_language
      if lang.present?
        lines << "- **Preferred language:** #{lang} — communicate with the user in this language"
      end

      lines.join("\n")
    end

    def build_mcp_descriptions(session)
      servers = resolve_mcp_servers_for_descriptions(session)
      return nil if servers.empty?

      lines = [ "## Available MCP Servers" ]
      lines << ""
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
      return nil if tools.empty?

      lines = [ "## Available Tools" ]
      lines << ""
      lines << "These tools are provided via the **palad-tools** MCP server. Call them through MCP."
      lines << ""
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

    def build_skills_section(session)
      skills = resolve_skills(session)
      return nil if skills.empty?

      lines = [ "## Skills" ]
      lines << ""
      skills.each do |skill|
        next if skill.content.blank?

        lines << "### #{skill.title.presence || skill.name}"
        lines << ""
        lines << skill.content
        lines << ""
      end
      lines.join("\n")
    end

    def build_general_instructions(session)
      lines = [ "## General Instructions" ]
      lines << ""
      lines << "Act to achieve the maximum result for the user."
      lines << "Use all available MCP servers and tools. Call `tools/list` on MCP servers to discover available capabilities."
      lines << "Write clean, production-quality code. Follow project conventions when present."

      if session.mode == "non_interactive"
        lines << ""
        lines << "## CRITICAL: Non-Interactive Mode"
        lines << ""
        lines << "This session runs **non-interactively** — there is NO human to respond."
        lines << "The user's prompt is the ONLY input you will receive. No follow-up is possible."
        lines << ""
        lines << "**Strict rules:**"
        lines << "- NEVER ask questions, request clarifications, or wait for input"
        lines << "- NEVER present options and ask the user to choose"
        lines << "- NEVER stop mid-task saying you need more information"
        lines << "- Make reasonable assumptions when details are missing and document them"
        lines << "- If a task is ambiguous, choose the most sensible interpretation and proceed"
        lines << ""
        lines << "**How to operate:**"
        lines << "1. Analyze the prompt and all available context (MCP tools, project files, skills)"
        lines << "2. Break the task into concrete steps"
        lines << "3. Execute each step fully — write files, create artifacts, run commands"
        lines << "4. Save all results to `/workspace/output/` so they persist after the session"
        lines << "5. At the end, write a summary of what was done and any assumptions made"
        lines << ""
        lines << "Your output MUST be actionable artifacts (documents, code, configs), not a conversation."
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

      safe_path = Shellwords.escape(path.to_s)
      result = runtime.exec(container_id, [ "sh", "-c", "cat #{safe_path}" ])
      stdout = result[0]
      exit_code = result[2]

      return nil unless exit_code.to_i.zero?

      stdout.join
    rescue StandardError => e
      Rails.logger.debug("[SessionContext] read_file(#{path}) failed: #{e.message}")
      nil
    end

    def extract_file_from_tar(tar_data, path)
      normalized = path.to_s.sub(%r{\A/}, "")
      return nil if normalized.blank?

      # Docker copy_from returns tar with basename only, not full path
      basename = File.basename(normalized)

      reader = Gem::Package::TarReader.new(StringIO.new(tar_data))
      contents = nil

      reader.each do |entry|
        entry_name = entry.full_name.sub(%r{\A\./}, "")
        if entry_name == normalized || entry_name == basename
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
        url: ENV.fetch("MCP_SERVER_URL", "http://web:4002/action_mcp"),
        transport: "streamable-http",
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
