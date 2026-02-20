# frozen_string_literal: true

# Container Workflow Service
# Dispatches container workflows via TemporalService
#
# - start_session: Dispatches to AgentContainerWorkflow (all agent session types)
# - start_tool_execution / execute_tool: Dispatches to ToolExecutionWorkflow

class ContainerWorkflowService
  TOOL_WORKFLOW_TIMEOUT = 3600           # 1 hour max for tools
  AGENT_WORKFLOW_TIMEOUT = 86_400        # 24 hours for agent sessions

  class << self
    # Start agent session workflow (auth_setup or agent_session)
    #
    # @param session [TerminalSession] Terminal session
    # @return [Hash] { ok: true/false, workflow_id:, run_id:, handle: }
    def start_session(session:)
      workflow_id = "agent-session-#{session.id}"

      TemporalService.start_workflow(
        agent_workflow,
        { session_id: session.id, mode: session.mode },
        id: workflow_id,
        execution_timeout: AGENT_WORKFLOW_TIMEOUT
      )
    end

    # Start tool execution workflow (async)
    #
    # @param tool [Tool] Tool to execute
    # @param parameters [Hash] Tool parameters
    # @param project [Project, nil] Project context
    # @param timeout [Integer] Execution timeout in seconds
    # @return [Hash] { ok: true/false, workflow_id:, run_id:, handle: }
    def start_tool_execution(tool:, parameters: {}, project: nil, timeout: 300)
      workflow_id = "tool-execution-#{tool.id}-#{SecureRandom.hex(8)}"

      TemporalService.start_workflow(
        tool_workflow,
        { tool_id: tool.id, parameters: parameters, project_id: project&.id, timeout: timeout },
        id: workflow_id,
        execution_timeout: TOOL_WORKFLOW_TIMEOUT
      )
    end

    # Execute tool and wait for result (blocking)
    #
    # @param tool [Tool] Tool to execute
    # @param parameters [Hash] Tool parameters
    # @param project [Project, nil] Project context
    # @param timeout [Integer] Execution timeout in seconds
    # @return [Hash] Tool execution result
    def execute_tool(tool:, parameters: {}, project: nil, timeout: 300)
      TemporalService.execute_workflow(
        tool_workflow,
        { tool_id: tool.id, parameters: parameters, project_id: project&.id, timeout: timeout }
      )
    end

    # Signal workflow to finish
    def signal_workflow(workflow_id, signal: :container_finished)
      TemporalService.send_signal(workflow_id, signal)
    end

    # Cancel workflow
    def cancel_workflow(workflow_id)
      TemporalService.cancel_workflow(workflow_id)
    end

    private

    def agent_workflow
      @agent_workflow ||= WorkflowService.agent_container_workflow
    end

    def tool_workflow
      @tool_workflow ||= WorkflowService.tool_execution_workflow
    end
  end
end
