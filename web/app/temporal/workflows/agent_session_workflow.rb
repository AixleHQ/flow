# frozen_string_literal: true

# Agent Session Workflow
# Starts an agent session with pre-loaded credentials
#
# Steps:
# 1. Start agent container with credentials (StartAgentSessionActivity)
# 2. Wait for user signal: session_finished (or timeout)
# 3. Stop and cleanup container (StopContainerActivity)
#
# Input: { terminal_session_id:, user_id:, agent_type: }
# Output: { status: :completed }

module Workflows
  class AgentSessionWorkflow < Base
    workflow_signal
    def session_finished
      @session_finished = true
    end

    def run(input)
      @session_finished = false

      # Step 1: Start container with credentials
      container_info = execute_activity(
        WorkflowService.agent_session_workflow.activities.start_agent_session_activity,
        input.to_h
      )

      # Step 2: Wait for user to finish session (blocking)
      # User sends signal via API or session times out
      Temporalio::Workflow.wait_condition { @session_finished }

      # Step 3: Stop container and cleanup
      container_id = container_info[:container_id] || container_info["container_id"]
      stop_input = { container_id: container_id }
      execute_activity(
        WorkflowService.agent_session_workflow.activities.stop_container_activity,
        stop_input
      )

      # Return success
      { status: :completed }
    end
  end
end
