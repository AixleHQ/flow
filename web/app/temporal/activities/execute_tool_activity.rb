# frozen_string_literal: true

# Execute Tool Activity
# Runs a custom tool in Docker container
#
# Input: { tool_id:, parameters: {}, project_id: nil, timeout: 300 }
# Returns: { exit_code:, stdout:, stderr:, duration_ms: }

module Activities
  class ExecuteToolActivity < Base
    def run(input)
      tool = Tool.find(input.tool_id)
      project = input.project_id.present? ? Project.find(input.project_id) : nil
      parameters = input.parameters || {}
      timeout = input.timeout || 300

      log(:info, "Executing tool: #{tool.name} (id: #{tool.id})")

      result = ToolExecutionService.execute(
        tool: tool,
        parameters: parameters,
        project: project,
        timeout: timeout
      )

      log(:info, "Tool execution completed: exit_code=#{result[:exit_code]}")

      result
    rescue ActiveRecord::RecordNotFound => e
      log(:error, "Tool or project not found: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: false)
    rescue ToolExecutionService::ExecutionError => e
      log(:error, "Execution error: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: false)
    rescue StandardError => e
      log(:error, "Unexpected error: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: true)
    end
  end
end
