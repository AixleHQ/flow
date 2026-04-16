# frozen_string_literal: true

module InternalTools
  class ReadToolResult < Base
    def execute
      tr = ToolResult.find_by(execution_id: params[:tool_result_id])
      return error("Tool result not found: #{params[:tool_result_id]}") unless tr

      success(ToolResultResource.new(tr, params: { url_host: Settings.container_asset_host }).to_json)
    end
  end
end
