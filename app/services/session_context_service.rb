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
  # Collects a structured log of everything injected into the container.
  # Written to /var/log/context.log for post-mortem debugging.
  class ContextLog
    def initialize(session)
      @session_id = session.id
      @agent_type = session.agent_type
      @mode = session.mode
      @started_at = Time.current
      @entries = []
    end

    def record(step, data)
      @entries << { step: step, data: data, at: Time.current.iso8601(3) }
    end

    def record_files(step, files_hash)
      return if files_hash.blank?

      @entries << { step: step, files: files_hash, at: Time.current.iso8601(3) }
    end

    def to_s
      lines = []
      lines << "=== Session Context Log ==="
      lines << "session_id: #{@session_id}"
      lines << "agent_type: #{@agent_type}"
      lines << "mode: #{@mode}"
      lines << "assembled_at: #{@started_at.iso8601(3)}"
      lines << ""

      @entries.each do |entry|
        if entry[:files]
          lines << "[#{entry[:at]}] #{entry[:step]}:"
          entry[:files].each do |path, content|
            lines << "--- #{path} ---"
            lines << content.to_s
            lines << "--- end #{path} ---"
            lines << ""
          end
        else
          lines << "[#{entry[:at]}] #{entry[:step]}: #{entry[:data].inspect}"
        end
      end

      lines << ""
      lines << "=== End Context Log ==="
      lines.join("\n")
    end
  end

  class << self
    # == Story 9.8: Unified Session Context Assembly ==

    # Orchestrate all session context injection steps in correct order.
    # Single entry point for AgentSessionStrategy#before_exec.
    #
    # @param container_id [String] Container identifier
    # @param session [TerminalSession] Session record
    # @param credential [AgentCredential, nil] Optional credential to inject
    def assemble_session_context(container_id, session, credential: nil)
      context_log = ContextLog.new(session)

      # Resolve MCP server names early — needed for pre-approving servers
      # in the credential config (e.g. Claude Code's enabledMcpjsonServers)
      mcp_server_names = build_all_servers(session).map(&:name)
      context_log.record(:mcp_servers, mcp_server_names)
      Rails.logger.info("[SessionContext] Pre-resolved MCP server names: #{mcp_server_names.inspect}")

      # Step 1: Credentials (optional)
      if credential.present?
        measure_step("credentials") do
          workflow_config = { enabled_mcp_servers: mcp_server_names }
          Rails.logger.info("[SessionContext] Writing credentials with workflow_config: #{workflow_config.inspect}")
          credential.write_to_container(container_id, workflow_config)
          context_log.record(:credentials, agent_type: credential.agent_type, config_keys: credential.config_data.keys, workflow_config: workflow_config)
        end
      end

      # Step 2: Config files
      measure_step("config_files") { inject_config_files(container_id, session) }
      context_log.record(:config_files, session.session_config&.dig("config_files")&.map { |f| f["path"] } || [])

      # Step 3: MCP config
      mcp_content = measure_step("mcp_config") { inject_mcp_config(container_id, session) }
      context_log.record_files(:mcp_config, mcp_content)

      # Step 4: Skills
      skill_content = measure_step("skills") { inject_skills(container_id, session) }
      context_log.record_files(:skills, skill_content)

      # Step 5: Context file (after skills — append to same file for Gemini)
      ctx_content = measure_step("context_file") { inject_context_file(container_id, session) }
      context_log.record_files(:context_file, ctx_content)

      # Step 6: Assets
      measure_step("assets") { inject_assets(container_id, session) }
      context_log.record(:assets, session.input_asset_ids || [])

      # Step 7: Repositories (shallow clone from GitHub)
      measure_step("repositories") { inject_repositories(container_id, session) }
      context_log.record(:repositories, session.repositories.pluck(:full_name))

      # Step 8: Write context log to container for debugging
      measure_step("context_log") { write_context_log(container_id, context_log) }

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
      return {} if skills.empty?

      adapter = adapter_for(session)
      files = adapter.skill_files(skills)
      return {} if files.blank?

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

      files
    end

    # == Story 9.7 → 25.7: Context File Injection (via Constructor) ==

    # Delegates context generation to SessionContextConstructor.
    # Produces XML-tagged markdown with priority-sorted sections.
    # Stores JSON metadata on session for traceability.
    def inject_context_file(container_id, session)
      result = SessionContextConstructor.build_result(session)
      content = result.render
      return {} if content.blank?

      adapter = adapter_for(session)
      path = adapter.context_file_path
      return {} if path.blank?

      expanded = expand_path(path, adapter.home_dir)
      write_file(container_id, expanded, content, adapter.tmpfs_uid)

      session.update_column(:context_metadata, result.to_json_hash)

      Rails.logger.info("[SessionContext] Injected context file: #{path} (#{content.bytesize} bytes, #{result.applied_builders.size} builders)")
      { path => content }
    end

    # == Story 9.4: MCP Config Injection ==

    # Generate and inject MCP server config files into container.
    # Always includes internal Palad MCP + external servers from session_config.
    # Delegates format generation to adapter, handles merge strategy.
    def inject_mcp_config(container_id, session)
      all_servers = build_all_servers(session)
      return {} if all_servers.empty?

      adapter = adapter_for(session)
      config_files = adapter.mcp_config(all_servers)
      return {} if config_files.blank?

      config_files.each do |path, content|
        expanded = expand_path(path, adapter.home_dir)
        write_mcp_file(container_id, expanded, content, adapter.mcp_merge_strategy, adapter.tmpfs_uid)
        Rails.logger.info("[SessionContext] Injected MCP config: #{path} (#{adapter.mcp_merge_strategy})")
      end

      config_files
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

    CONTEXT_LOG_PATH = "/var/log/context.log"

    def write_context_log(container_id, context_log)
      runtime.copy_to(container_id, CONTEXT_LOG_PATH, context_log.to_s)
    rescue => e
      Rails.logger.warn("[SessionContext] Failed to write context log: #{e.message}")
    end

    # == Timing ==

    def measure_step(name)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
      Rails.logger.info("[SessionContext] Step '#{name}' completed in #{elapsed}ms")
      result
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

    # Legacy context builders removed in Story 25.7.
    # Context generation now handled by SessionContextConstructor and ContextBuilders::*.

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
      external = resolve_mcp_servers(session).map { |s| resolve_server_secrets(s, effective_items) }

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

    def resolve_server_secrets(server, effective_items)
      resolved_headers = (server.headers || {}).transform_values do |value|
        resolve_embedded_references(value, effective_items)
      end

      resolved_env = (server.env || {}).transform_values do |value|
        resolve_embedded_references(value, effective_items)
      end

      attrs = {
        name: server.name,
        url: server.url,
        transport: server.transport.to_s,
        headers: resolved_headers,
        env: resolved_env
      }

      if server.transport_stdio?
        attrs[:command] = server.command_executable
        attrs[:args] = server.command_args
      end

      OpenStruct.new(attrs)
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
      Thread.current[:session_context_runtime] ||= ContainerRuntime.build
    end
  end
end
