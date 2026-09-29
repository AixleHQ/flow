# frozen_string_literal: true

module InternalTools
  class ReadToolResult < Base
    tool do
      display_name "Read Tool Result"
      description "Retrieve status and download URLs for an async tool execution. Returns presigned URLs valid for 1 hour. Download files using curl: curl -o /tmp/result.json <url>"
      tags :async_results
      inject_when :container_tools_present
      user_attachable false
      input_schema({
        type: "object",
        required: %w[tool_result_id],
        properties: {
          tool_result_id: {
            type: "string",
            description: "Execution ID (e.g. tr-abc123...)"
          }
        }
      })
    end

    def execute
      tr = readable_results.find_by(execution_id: params[:tool_result_id])
      return error("Tool result not found: #{params[:tool_result_id]}") unless tr

      success(ToolResultResource.new(tr, params: { url_host: Settings.container_asset_host }).to_json)
    end

    private

    # Results this session started, plus those of the other sessions in the same
    # workflow run (a later step may poll a tool an earlier step launched). The
    # execution id is random, but it is also the only thing the agent supplies.
    def readable_results
      session_ids = [ session&.id ].compact
      if workflow_run
        session_ids += TerminalSession.joins(:step_run).where(step_runs: { workflow_run_id: workflow_run.id }).pluck(:id)
      end
      ToolResult.where(terminal_session_id: session_ids.uniq)
    end
  end
end
