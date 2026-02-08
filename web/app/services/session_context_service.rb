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
class SessionContextService
  class << self
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
