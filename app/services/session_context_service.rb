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

      # Step 6: Assets
      measure_step("assets") { inject_assets(container_id, session) }

      # Step 7: Repositories (shallow clone from GitHub)
      measure_step("repositories") { inject_repositories(container_id, session) }

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

      # Section 3: Workspace layout
      sections << build_workspace_layout(session)

      # Section 4: Available shell tools
      sections << build_shell_tools_section

      # Section 5: Available MCP servers
      mcp = build_mcp_descriptions(session)
      sections << mcp if mcp.present?

      # Section 6: Available tools
      tools = build_tool_descriptions(session)
      sections << tools if tools.present?

      # Section 7: Skills (when adapter embeds them into context file)
      if adapter.includes_skills_in_context?
        skills_section = build_skills_section(session)
        sections << skills_section if skills_section.present?
      end

      # Section 8: Repositories
      repos_section = build_repositories_section(session)
      sections << repos_section if repos_section.present?

      # Section 9: General instructions
      sections << build_general_instructions(session)

      # Workflow instructions (placeholder for future use)
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

    def build_workspace_layout(session)
      has_assets = session.input_asset_ids.present?
      has_repos  = session.repository_ids.present?

      lines = [ "## Workspace Layout" ]
      lines << ""
      lines << "Your working directory is `/workspace`."
      lines << ""
      lines << "- **`/workspace/outputs/`** — Put all results, artifacts, and deliverables here. Contents will be collected after the session."

      if has_assets
        lines << "- **`/workspace/assets/`** — Read-only reference documents provided for this task. " \
                 "Do NOT modify these files. If you need to extend an asset, copy it to `/workspace/outputs/` with the full content and edit the copy."
      end

      if has_repos
        lines << "- **`/workspace/repo/`** — Code repositories to work with. See the \"Available Repositories\" section for details."
      end

      lines.join("\n")
    end

    def build_shell_tools_section
      <<~MD.strip
        ## Available Shell Tools

        The following command-line tools are pre-installed and available:

        | Tool | Description | Example |
        |------|-------------|---------|
        | `tree` | Display directory structure | `tree -d -L 2` (dirs only), `tree -L 3 /workspace/repo/` |
        | `cloc` | Count lines of code by language | `cloc .`, `cloc --by-file /workspace/repo/` |
        | `rg` | ripgrep — fast code search | `rg 'TODO' --type ruby`, `rg -l 'class.*Service'` |
        | `fd` | Fast file finder | `fd -e rb`, `fd -e tsx -x wc -l {}` |
        | `jq` | JSON processor | `jq '.dependencies' package.json` |
        | `git` | Version control | `git log --oneline -20`, `git diff` |
        | `curl` | HTTP requests | `curl -s https://api.example.com` |
      MD
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

      has_container_tools = tools.any? { |t| t.respond_to?(:execution_mode) && t.execution_mode.to_s == "container" }

      lines = ["## Available Tools"]
      lines << ""
      lines << "These tools are provided via the **palad-tools** MCP server. Call them through MCP."
      lines << ""

      if has_container_tools
        lines << tool_execution_modes_section
        lines << ""
      end

      tools.each do |tool|
        mode = tool.respond_to?(:execution_mode) ? tool.execution_mode.to_s : "app"
        marker = mode == "container" ? "⏳ container" : "⚡ app"
        lines << "### #{tool.name} #{marker}"
        desc = [tool.display_name, tool.description].compact.join(" — ")
        lines << desc if desc.present?
        lines << (mode == "container" ? "Returns: execution ID → use read_tool_result to get results" : "Returns: direct result")
        if tool.input_schema.present? && tool.input_schema["properties"].present?
          params = tool.input_schema["properties"].map { |k, v| "#{k} (#{v['type']})" }.join(", ")
          lines << "Parameters: #{params}" if params.present?
        end
        lines << ""
      end
      lines.join("\n")
    end

    def tool_execution_modes_section
      <<~MD.strip
        ### Tool Execution Modes

        Tools on this platform work in two modes:

        **Instant tools (⚡ app)** return results directly in the MCP response. Use them normally.

        **Container tools (⏳ container)** run in Docker containers and may take seconds to minutes. They work asynchronously:

        1. **Call the tool** — you receive an execution ID (e.g. `tr-a1b2c3d4e5f6`)
        2. **Check status** — call `read_tool_result(tool_result_id: "tr-...")`.
           If `state` is `processing`, wait and try again.
           If `state` is `completed` or `failed`, proceed to step 3.
        3. **Download results** — the response contains presigned URLs (`stdout_url`, `result_data_url`, etc.).
           Download them to local files:
           ```
           curl -sS -o /workspace/result.json "<result_data_url>"
           ```
        4. **Process locally** — read and analyze the downloaded files as needed.

        Important:
        - NEVER expect container tool output directly in the MCP response — you only get an ID.
        - Presigned URLs expire in 1 hour. Call `read_tool_result` again for fresh URLs if needed.
        - `result_data_url` contains parsed JSON (if the tool output was valid JSON). Prefer it over `stdout_url`.
        - `output_url` is a tar.gz archive of additional files collected from the tool container (if any).
      MD
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
        lines << "4. Save all results to `/workspace/outputs/` so they persist after the session"
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

    # == Asset Injection ==

    def inject_assets(container_id, session)
      ids = session.input_asset_ids
      return if ids.blank?

      assets = Asset.where(id: ids).includes(:versions).to_a
      missing = ids - assets.map(&:id)
      missing.each { |id| Rails.logger.warn("[SessionContext] Asset #{id} not found, skipping") }

      adapter = adapter_for(session)
      uid = adapter.tmpfs_uid

      assets.each do |asset|
        version = asset.latest_version
        unless version&.file
          Rails.logger.warn("[SessionContext] Asset '#{asset.name}' has no file, skipping")
          next
        end

        folder = asset.folder.present? ? "#{asset.folder}/" : ""
        target_path = "/workspace/assets/#{folder}#{asset.name}"
        url = container_accessible_url(version.file.url)

        download_file_to_container(container_id, url, target_path, uid)
      end
    end

    # == Repository Injection ==

    def inject_repositories(container_id, session)
      ids = session.repository_ids
      return if ids.blank?

      repos = Repository.where(id: ids).includes(:integration).to_a
      return if repos.empty?

      adapter = adapter_for(session)
      uid = adapter.tmpfs_uid

      repos.group_by(&:integration_id).each do |_integration_id, group_repos|
        integration = group_repos.first.integration
        unless integration&.active?
          group_repos.each { |r| record_failed_repo(session, r, "Integration not active") }
          next
        end

        begin
          repo_names = group_repos.map(&:repo_name)
          token = Github::TokenService.new(integration).generate_installation_token(repositories: repo_names)
        rescue => e
          Rails.logger.error("[SessionContext] Failed to generate token for integration #{integration.id}: #{e.message}")
          group_repos.each { |r| record_failed_repo(session, r, "Token generation failed: #{e.message}") }
          next
        end

        group_repos.each { |repo| clone_repository(container_id, repo, token, uid, session) }
      end
    end

    def clone_repository(container_id, repo, token, uid, session)
      clone_url = "https://x-access-token:#{token}@github.com/#{repo.full_name}.git"
      target_path = "/workspace/repo/#{repo.repo_name}"
      branch = Shellwords.escape(repo.source_branch)

      cmd = [ "sh", "-c", "git clone --depth=1 --branch=#{branch} #{clone_url} #{target_path} && chown -R #{uid}:#{uid} #{target_path}" ]
      result = runtime.exec(container_id, cmd)
      exit_code = result[2]

      if exit_code.to_i.zero?
        repo.update_column(:last_fetched_at, Time.current)
        Rails.logger.info("[SessionContext] Cloned repository: #{repo.full_name} → #{target_path}")
      else
        stderr = Array(result[1]).join
        raise "git clone exited with #{exit_code}: #{stderr}"
      end
    rescue => e
      Rails.logger.error("[SessionContext] Failed to clone #{repo.full_name}: #{e.message}")
      record_failed_repo(session, repo, e.message)
    end

    def record_failed_repo(session, repo, error)
      meta = session.metadata || {}
      meta["failed_repos"] ||= []
      meta["failed_repos"] << { "id" => repo.id, "full_name" => repo.full_name, "error" => error.to_s.truncate(500) }
      session.update_column(:metadata, meta)
    end

    def build_repositories_section(session)
      ids = session.repository_ids
      return nil if ids.blank?

      repos = Repository.where(id: ids).to_a
      return nil if repos.empty?

      failed = (session.metadata || {}).fetch("failed_repos", []).map { |f| f["id"] }
      cloned = repos.reject { |r| failed.include?(r.id) }
      return nil if cloned.empty?

      lines = [ "## Available Repositories" ]
      lines << ""
      lines << "The following code repositories have been cloned into this session:"
      lines << ""
      lines << "| ID | Repository | Path | Branch | Purpose |"
      lines << "|---|---|---|---|---|"
      cloned.each do |repo|
        purpose = repo.purpose.presence || "—"
        lines << "| #{repo.id} | #{repo.full_name} | /workspace/repo/#{repo.repo_name} | #{repo.source_branch} | #{purpose} |"
      end
      lines << ""
      lines << "Use the repository **ID** when calling tools that require a `repository_id` parameter."
      lines.join("\n")
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

    def download_file_to_container(container_id, url, target_path, uid)
      safe_dir = Shellwords.escape(File.dirname(target_path))
      safe_path = Shellwords.escape(target_path)
      safe_url = Shellwords.escape(url)

      cmd = [ "sh", "-c", "mkdir -p #{safe_dir} && curl -fsSL -o #{safe_path} #{safe_url} && chown #{uid}:#{uid} #{safe_path}" ]
      result = runtime.exec(container_id, cmd)
      exit_code = result[2]

      if exit_code.to_i.zero?
        Rails.logger.info("[SessionContext] Downloaded asset: #{target_path}")
      else
        stderr = Array(result[1]).join
        Rails.logger.error("[SessionContext] Failed to download asset to #{target_path}: exit=#{exit_code} #{stderr}")
      end
    end

    def container_accessible_url(url)
      host = Settings.container_asset_host
      return url if host.blank?

      override = URI.parse(host.start_with?("http") ? host : "http://#{host}")
      uri = URI.parse(url)
      uri.scheme = override.scheme
      uri.host = override.host
      uri.port = override.port
      uri.to_s
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
        url: Settings.mcp.server_url,
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
