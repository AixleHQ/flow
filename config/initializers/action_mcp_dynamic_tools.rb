# frozen_string_literal: true

# ActionMCP Dynamic Tools Patch
# Enables session-specific tool resolution and execution via Temporal
#
# This patch overrides ActionMCP's default tools/list and tools/call handlers
# to dynamically resolve tools based on the authenticated session.

Rails.application.config.after_initialize do
  next unless defined?(ActionMCP)

  # Allow terminal_session as an identity key in the gateway
  ActionMCP.configure do |config|
    config.allowed_identity_keys = %w[user api_key jwt bearer token account session terminal_session]
  end

  # Extend Current to hold terminal_session
  ActionMCP::Current.class_eval do
    attribute :terminal_session
  end

  # Patch Tools module for dynamic tool resolution
  ActionMCP::Server::Tools.module_eval do
    MANAGED_NAMESPACE_PREFIX = "mcp__"
    MANAGED_NAMESPACE_SEPARATOR = "__"

    # Override tools/list to return session-specific tools.
    #
    # Managed MCP servers (e.g. Coder) re-expose the underlying Tool records
    # with a `mcp__<server-name>__<tool>` namespace so that multiple
    # integrations in the same scope surface independently to the agent.
    def send_tools_list(request_id, params = {})
      session = current_terminal_session!(request_id)
      return unless session

      tools = session.available_tools.map { |tool| serialize_tool(tool) }

      session.mcp_servers.where(kind: "managed", enabled: true).each do |server|
        managed_tools_for(server).each do |tool|
          tools << serialize_tool(tool, namespace: server.name)
        end
      end

      send_jsonrpc_response(request_id, result: { tools: tools })
    end

    # Override tools/call to execute via Temporal
    def send_tools_call(request_id, tool_name, arguments, _meta = {})
      session = current_terminal_session!(request_id)
      return unless session

      mcp_server   = nil
      resolved_name = tool_name

      if (parsed = parse_managed_namespace(tool_name))
        server_name, resolved_name = parsed
        mcp_server = session.mcp_servers.where(kind: "managed", enabled: true).find_by(name: server_name)
        unless mcp_server
          send_jsonrpc_error(request_id, :method_not_found, "Managed MCP server '#{server_name}' not bound to this session")
          return
        end
      end

      tool = resolve_tool_for_call(session, resolved_name, mcp_server)

      unless tool
        send_jsonrpc_error(request_id, :method_not_found, "Tool '#{tool_name}' not available")
        return
      end

      begin
        result = execute_tool(tool, arguments, session, mcp_server: mcp_server)
        content = build_response_content(result)
        send_jsonrpc_response(request_id, result: { content: content })
      rescue StandardError => e
        Rails.logger.error("[MCP] Tool execution failed: #{e.message}")
        send_jsonrpc_error(request_id, :internal_error, "Tool execution failed: #{e.message}")
      end
    end

    def serialize_tool(tool, namespace: nil)
      schema = tool.input_schema.presence || { "type" => "object", "properties" => {}, "required" => [] }
      schema = schema.deep_stringify_keys if schema.respond_to?(:deep_stringify_keys)
      name   = namespace.present? ? "mcp__#{namespace}__#{tool.name}" : tool.name

      {
        "name" => name,
        "description" => tool.description || tool.display_name,
        "inputSchema" => schema
      }
    end

    def resolve_tool_for_call(session, base_name, mcp_server)
      if mcp_server&.managed?
        names = Integrations::ManagedMCPToolRegistry.tool_names_for(mcp_server.integration&.provider)
        return nil unless names.include?(base_name)
        Tool.system_tools.enabled.not_deleted.find_by(name: base_name)
      else
        session.available_tools.detect { |t| t.name == base_name }
      end
    end

    # Parse a tool name of the form `mcp__<server-name>__<tool-name>` into a
    # [server_name, tool_name] pair. Splits on the first `__` after the
    # `mcp__` prefix so server names containing dashes work; tool names
    # containing underscores also work. Returns nil if the name does not
    # match the managed-namespace shape.
    def parse_managed_namespace(name)
      return nil unless name.is_a?(String) && name.start_with?(MANAGED_NAMESPACE_PREFIX)

      rest = name.delete_prefix(MANAGED_NAMESPACE_PREFIX)
      idx  = rest.index(MANAGED_NAMESPACE_SEPARATOR)
      return nil unless idx

      [ rest[0...idx], rest[(idx + MANAGED_NAMESPACE_SEPARATOR.length)..] ]
    end

    def managed_tools_for(server)
      names = Integrations::ManagedMCPToolRegistry.tool_names_for(server.integration&.provider)
      return [] if names.empty?

      Tool.system_tools.enabled.not_deleted.where(name: names).to_a
    end

    private

    def current_terminal_session!(request_id)
      session = ActionMCP::Current.terminal_session
      return session if session.present?

      Rails.logger.error("[MCP] Authenticated request reached tools handler without terminal_session context")
      send_jsonrpc_error(request_id, :internal_error, "Terminal session context is missing for this MCP request")
      nil
    end

    def execute_tool(tool, arguments, session, mcp_server: nil)
      params = resolve_repository_params(arguments || {}, session)

      if tool.execution_mode.app?
        tool.execute(
          parameters: params,
          project: session.project,
          session: session,
          mcp_server: mcp_server
        )
      else
        tool_result = ToolResult.create!(
          tool: tool,
          terminal_session: session,
          step_run: session.step_run,
          execution_id: ToolResult.generate_id,
          state: "processing"
        )

        tool.execute(
          parameters: params,
          project: session.project,
          session: session,
          timeout: 300,
          tool_result_id: tool_result.id
        )

        { exit_code: 0, stdout: tool_result.execution_id }
      end
    end

    # When arguments contain repository_id, validate ownership and resolve
    # REPO (full_name) + GITHUB_TOKEN from the integration automatically.
    def resolve_repository_params(arguments, session)
      repo_id = arguments["repository_id"] || arguments[:repository_id]
      return arguments unless repo_id.present?

      repo = session.repositories.find_by(id: repo_id)
      raise "Repository #{repo_id} is not attached to this session" unless repo

      token = Github::TokenService.new(repo.integration).generate_installation_token

      arguments.except("repository_id", :repository_id).merge(
        "REPO" => repo.full_name,
        "GITHUB_TOKEN" => token,
        "BRANCH" => arguments["BRANCH"].presence || repo.source_branch
      )
    end

    def build_response_content(result)
      content = []

      # Handle both symbol and string keys
      exit_code = result[:exit_code] || result["exit_code"]
      stdout = result[:stdout] || result["stdout"]
      stderr = result[:stderr] || result["stderr"]

      if exit_code == 0
        content << { type: "text", text: stdout } if stdout.present?
      else
        content << { type: "text", text: "Error (exit #{exit_code}):" }
        content << { type: "text", text: stderr } if stderr.present?
        content << { type: "text", text: stdout } if stdout.present?
      end

      content << { type: "text", text: "(no output)" } if content.empty?
      content
    end
  end
end
