# frozen_string_literal: true

# Tool Execution Workflow
# Executes a custom tool in Docker container
#
# Steps:
# 1. Pull Docker image (if not cached)
# 2. Execute tool in container (with timeout)
#
# Input: { tool_id:, docker_image:, parameters: {}, project_id: nil, timeout: 300 }
# Output: { exit_code:, stdout:, stderr:, duration_ms: }
#
# Note: docker_image must be passed in input because workflows must be deterministic
# (no database access allowed inside workflow code)

module Workflows
  class ToolExecutionWorkflow < Base
    DEFAULT_TIMEOUT = 300 # 5 minutes
    MAX_TIMEOUT = 1800    # 30 minutes

    def run(input)
      docker_image = input.docker_image
      raise ArgumentError, "docker_image is required" if docker_image.blank?

      timeout = [ input.timeout || DEFAULT_TIMEOUT, MAX_TIMEOUT ].min

      # Step 1: Pull Docker image (idempotent - skips if cached)
      execute_activity(
        WorkflowService.tool_execution_workflow.activities.pull_docker_image_activity,
        { image: docker_image }
      )

      # Step 2: Execute tool in container
      result = execute_activity(
        WorkflowService.tool_execution_workflow.activities.execute_tool_activity,
        {
          tool_id: input.tool_id,
          parameters: input.parameters || {},
          project_id: input.project_id,
          timeout: timeout
        }
      )

      # Return structured result
      {
        exit_code: result[:exit_code] || result["exit_code"],
        stdout: result[:stdout] || result["stdout"] || "",
        stderr: result[:stderr] || result["stderr"] || "",
        duration_ms: result[:duration_ms] || result["duration_ms"] || 0
      }
    end
  end
end
