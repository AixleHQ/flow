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
    # Override tools/list to return session-specific tools
    def send_tools_list(request_id, params = {})
      session = ActionMCP::Current.terminal_session
      return super if session.nil?

      tools = session.available_tools.map do |tool|
        schema = tool.input_schema.presence || { "type" => "object", "properties" => {}, "required" => [] }
        schema = schema.deep_stringify_keys if schema.respond_to?(:deep_stringify_keys)

        {
          "name" => tool.name,
          "description" => tool.description || tool.display_name,
          "inputSchema" => schema
        }
      end

      send_jsonrpc_response(request_id, result: { tools: tools })
    end

    # Override tools/call to execute via Temporal
    def send_tools_call(request_id, tool_name, arguments, _meta = {})
      session = ActionMCP::Current.terminal_session
      return super if session.nil?

      tool = session.available_tools.detect { |t| t.name == tool_name }

      unless tool
        send_jsonrpc_error(request_id, :method_not_found, "Tool '#{tool_name}' not available")
        return
      end

      begin
        result = execute_tool(tool, arguments, session)
        content = build_response_content(result)
        send_jsonrpc_response(request_id, result: { content: content })
      rescue StandardError => e
        Rails.logger.error("[MCP] Tool execution failed: #{e.message}")
        send_jsonrpc_error(request_id, :internal_error, "Tool execution failed: #{e.message}")
      end
    end

    private

    def execute_tool(tool, arguments, session)
      params = resolve_repository_params(arguments || {}, session)

      if tool.execution_mode.app?
        tool.execute(
          parameters: params,
          project: session.project,
          session: session
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
