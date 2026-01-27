# frozen_string_literal: true

# Agent Authentication Workflow
# Orchestrates the authentication process for agent CLIs
#
# Steps:
# 1. Start authentication container (StartAuthTerminalActivity)
# 2. Wait for user signal: authentication_finished
# 3. Collect artifacts from container (CollectArtifactsActivity)
# 4. Stop and cleanup container (StopContainerActivity)
#
# Input: { terminal_session_id:, user_id:, agent_type: }
# Output: { status: :completed, artifacts: hash }

module Workflows
  class AgentAuthWorkflow < Base
    workflow_signal
    def authentication_finished
      @auth_finished = true
    end

    workflow_signal
    def session_cancelled
      @cancelled = true
    end

    def run(input)
      @auth_finished = false
      @cancelled = false

      # Step 1: Start container and get WebSocket URL
      container_info = execute_activity(
        WorkflowService.agent_auth_workflow.activities.start_auth_terminal_activity,
        input.to_h
      )

      container_id = container_info[:container_id] || container_info["container_id"]

      # Step 2: Wait for user to finish authentication OR cancel
      Temporalio::Workflow.wait_condition { @auth_finished || @cancelled }

      # Step 3: Collect artifacts ONLY if auth finished (not cancelled)
      if @auth_finished && !@cancelled
        collect_input = {
          terminal_session_id: input.terminal_session_id,
          container_id: container_id,
          agent_type: input.agent_type
        }
        artifacts = execute_activity(
          WorkflowService.agent_auth_workflow.activities.collect_artifacts_activity,
          collect_input
        )
      end

      # Step 4: Stop container and cleanup (always)
      stop_input = {
        container_id: container_id,
        terminal_session_id: input.terminal_session_id
      }
      execute_activity(
        WorkflowService.agent_auth_workflow.activities.stop_container_activity,
        stop_input
      )

      # Return status
      if @cancelled
        { status: :cancelled }
      else
        { status: :completed, artifacts: artifacts }
      end
    end
  end
end
