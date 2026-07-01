# frozen_string_literal: true

class WorkflowDuplicator
  # Deep-copies a workflow's dependency resources (agents, skills, MCP servers,
  # custom tools) into a target Project as project-local, independently-editable
  # rows, and remaps the source IDs to the new project-local IDs. See #302.
  #
  # Boundaries / product decisions (see design doc §3–§5):
  # - Never copies ConfigItem rows (the sole secrets boundary). MCP env/headers
  #   are copied VERBATIM — config_item:NAME references carry no secret material.
  # - Platform/System resources (System agents, platform tools, internal MCP
  #   servers) are passed through by ID — they are project-agnostic.
  # - Managed MCP servers are never deep-copied: passed through if still visible
  #   in the target project, otherwise the reference is dropped.
  # - Assets / repositories / integrations are intentionally NOT copied.
  # - Idempotent by (scope, name): a same-named project-local row is reused.
  #
  # After copying, #summary reports what was skipped / needs manual setup so the
  # UI can show a "needs setup" notice.
  class DependencyCopier
    # config_item:NAME references live inside MCP env/headers values.
    CONFIG_ITEM_REF = /config_item:(\w+)/

    def initialize(source:, target_project:)
      @source = source
      @project = target_project
      @not_copied = {
        config_items: [],   # config_item:NAME refs the workflow relies on
        managed_mcp_servers: [], # dropped managed MCP servers (not visible in target)
        gated_tools: [],    # copied tools hidden until an integration is connected
        assets: false,      # assets intentionally not copied
        repositories: false, # repositories intentionally not copied
        integrations: false  # integrations intentionally not copied
      }
    end

    # ---- Mappers (return values are written straight into step columns /
    # workflow config). Array mappers ALWAYS return an array (never nil): the
    # steps JSONB columns are NOT NULL. agent_id is nullable, so nil is fine.

    def map_agent_id(id)
      return id if id.nil? || @project.nil?

      agent_map.fetch(id) { agent_map[id] = copy_agent(id) }
    end

    def map_skill_ids(ids)
      map_ids(ids) { |id| skill_map.fetch(id) { skill_map[id] = copy_skill(id) } }
    end

    def map_tool_ids(ids)
      map_ids(ids) { |id| tool_map.fetch(id) { tool_map[id] = copy_tool(id) } }
    end

    def map_mcp_server_ids(ids)
      map_ids(ids) { |id| mcp_map.fetch(id) { mcp_map[id] = copy_mcp_server(id) } }
    end

    # Human-readable summary of what was NOT copied / needs setup. Returns nil
    # when nothing needs attention, so callers can conditionally surface it.
    def summary
      note_intentional_skips
      messages = []

      if @not_copied[:config_items].any?
        names = @not_copied[:config_items].uniq.sort.join(", ")
        messages << "Secrets/config are not copied — add these config items in the project: #{names}."
      end

      if @not_copied[:managed_mcp_servers].any?
        names = @not_copied[:managed_mcp_servers].uniq.sort.join(", ")
        messages << "Managed MCP servers were not copied (connect the integration): #{names}."
      end

      if @not_copied[:gated_tools].any?
        names = @not_copied[:gated_tools].uniq.sort.join(", ")
        messages << "Some tools require an integration before they are usable: #{names}."
      end

      messages << "Assets, repositories and integrations are not copied — set them up in the project as needed."

      { needs_setup: messages }
    end

    private

    # nil-safe, always-array id mapper. Uses filter_map so pass-through and
    # copied ids both land in an Array, satisfying the NOT NULL jsonb columns.
    def map_ids(ids)
      return ids || [] if @project.nil? || ids.blank?

      ids.filter_map { |id| yield(id) }
    end

    def agent_map = @agent_map ||= {}
    def skill_map = @skill_map ||= {}
    def tool_map  = @tool_map ||= {}
    def mcp_map   = @mcp_map ||= {}

    # ---- Agent -------------------------------------------------------------

    def copy_agent(id)
      agent = Agent.find_by(id: id)
      return id unless agent                                  # unknown → leave as-is (defensive)
      return id if agent.system?                              # System → shared, pass through
      return id if project_local?(agent)                      # already target-local

      existing = @project.agents.find_by(name: agent.name)    # name unique per scope → reuse
      return existing.id if existing

      @project.agents.create!(
        name: agent.name, title: agent.title, icon: agent.icon,
        persona: agent.persona, communication_style: agent.communication_style,
        principles: agent.principles, source: agent.source
      ).id
    end

    # ---- Skill -------------------------------------------------------------

    def copy_skill(id)
      skill = Skill.find_by(id: id)
      return id unless skill
      return id if project_local?(skill)

      existing = Skill.for_project(@project).find_by(name: skill.name)
      return existing.id if existing

      Skill.create!(
        scope: @project,
        name: skill.name, title: skill.title, description: skill.description,
        package: skill.package, source: skill.source, source_url: skill.source_url,
        content: skill.content, references_data: skill.references_data, install_count: 0
      ).id
    end

    # ---- MCPServer ---------------------------------------------------------

    def copy_mcp_server(id)
      server = MCPServer.find_by(id: id)
      return id unless server
      return id if server.internal?                           # internal → shared, pass through

      if server.managed?
        # Never deep-copy managed servers (owned by an Integration via FK
        # cascade). Pass through if still visible in the target; drop otherwise.
        return id if MCPServer.visible_for_project(@project).exists?(id: server.id)

        @not_copied[:managed_mcp_servers] << server.picker_name
        return nil
      end

      return id if project_local?(server)

      collect_config_item_refs(server.env)
      collect_config_item_refs(server.headers)

      existing = MCPServer.for_project(@project).find_by(name: server.name)
      return existing.id if existing

      MCPServer.create!(
        scope: @project, kind: "custom",
        name: server.name, display_name: server.display_name,
        url: server.url, transport: server.transport, description: server.description,
        command: server.command, args: server.args, enabled: server.enabled,
        env: server.env, headers: server.headers # verbatim — secrets live in ConfigItem, not here (D3)
      ).id
    end

    # ---- Tool --------------------------------------------------------------

    def copy_tool(id)
      tool = Tool.find_by(id: id)
      return id unless tool
      return id if tool.platform_tool?                        # system/internal/workflow/meta → shared
      return id if tool.deleted?                              # skip soft-deleted source tools
      return id if project_local?(tool)

      collect_config_item_names(tool.required_config_items)
      @not_copied[:gated_tools] << tool.picker_name if tool.requires_integration.present?

      existing = Tool.for_project(@project).find_by(name: tool.name)
      return existing.id if existing

      new_tool = Tool.create!(
        scope: @project, kind: "custom",
        name: tool.name, display_name: tool.display_name, description: tool.description,
        docker_image: tool.docker_image, command: tool.command,
        execution_mode: tool.execution_mode, input_schema: tool.input_schema,
        required_config_items: tool.required_config_items, enabled: tool.enabled,
        requires_integration: tool.requires_integration # D9 — kept; tool stays gated until integration connected
      )

      copy_tool_files(tool, new_tool)
      new_tool.id
    end

    # Replicates tool_files, including binary Shrine attachments (file_data),
    # not just the legacy text `content` column (§4 Tool / D6).
    def copy_tool_files(source_tool, new_tool)
      source_tool.tool_files.each do |tf|
        attrs = { path: tf.path, content: tf.content }
        # Copy the Shrine file attachment verbatim for binary tool files by
        # reusing the stored file_data — otherwise binary bytes are lost.
        attrs[:file_data] = tf.file_data if tf.file_data.present?
        new_tool.tool_files.create!(attrs)
      end
    end

    # ---- Config-item / summary helpers ------------------------------------

    def collect_config_item_refs(jsonb)
      return if jsonb.blank?

      jsonb.each_value do |value|
        next unless value.is_a?(String)

        value.scan(CONFIG_ITEM_REF).each { |(name)| @not_copied[:config_items] << name }
      end
    end

    def collect_config_item_names(names)
      return if names.blank?

      Array(names).each { |name| @not_copied[:config_items] << name.to_s.upcase }
    end

    def project_local?(resource)
      resource.scope_type == "Project" && resource.scope_id == @project.id
    end

    def note_intentional_skips
      @not_copied[:assets] = true
      @not_copied[:repositories] = true
      @not_copied[:integrations] = true
    end
  end
end
