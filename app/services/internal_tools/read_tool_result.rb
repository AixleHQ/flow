# frozen_string_literal: true

module InternalTools
  class ReadToolResult < Base
    tool do
      display_name "Read Tool Result"
      description "Retrieve status and download URLs for an async tool execution. Returns presigned URLs valid for 1 hour. Download files using curl: curl -o /tmp/result.json <url>"
      tags :async_results
      inject_when :container_tools_present
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
      tr = ToolResult.find_by(execution_id: params[:tool_result_id])
      return error("Tool result not found: #{params[:tool_result_id]}") unless tr

      success(ToolResultResource.new(tr, params: { url_host: Settings.container_asset_host }).to_json)
    end
  end
end
