# frozen_string_literal: true

module Tools
  # Executes one tool call for the MCP server and shapes the result into MCP
  # content. Extracted verbatim from the old actionmcp monkey-patch so the
  # wire contract (execution_id-as-stdout for async container tools, the
  # "Error (exit N):" text shape) survives the transport swap.
  module CallExecutor
    CONTAINER_CALL_TIMEOUT = 300

    class << self
      def execute(tool, arguments, session, mcp_server: nil)
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
            timeout: CONTAINER_CALL_TIMEOUT,
            tool_result_id: tool_result.id
          )

          { exit_code: 0, stdout: tool_result.execution_id }
        end
      end

      def response_content(result)
        content = []

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

      private

      # When arguments contain repository_id, validate ownership and resolve
      # REPO (full_name) + GITHUB_TOKEN from the integration automatically.
      def resolve_repository_params(arguments, session)
        arguments = arguments.deep_stringify_keys if arguments.respond_to?(:deep_stringify_keys)
        repo_id = arguments["repository_id"]
        return arguments unless repo_id.present?

        repo = session.repositories.find_by(id: repo_id)
        raise "Repository #{repo_id} is not attached to this session" unless repo

        if repo.public_source?
          raise "Repository #{repo.full_name} is a public read-only source — it has no credentials, " \
                "so tools that write to it cannot run. Attach it through a GitHub integration first."
        end
        raise "Repository #{repo.full_name} is not a GitHub repository" unless repo.integration.github?

        token = Github::TokenService.new(repo.integration).generate_installation_token

        arguments.except("repository_id").merge(
          "REPO" => repo.full_name,
          "GITHUB_TOKEN" => token,
          "BRANCH" => arguments["BRANCH"].presence || repo.source_branch
        )
      end
    end
  end
end
