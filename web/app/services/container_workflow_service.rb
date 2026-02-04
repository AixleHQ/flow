# frozen_string_literal: true

# Container Workflow Service
# Helper service for starting container workflows via TemporalService
#
# Provides convenience methods for:
# - Tool execution
# - Agent authentication
# - Agent sessions
#
# All methods use UnifiedContainerWorkflow via TemporalService

class ContainerWorkflowService
  TOOL_WORKFLOW_TIMEOUT = 3600           # 1 hour max for tools
  AGENT_WORKFLOW_TIMEOUT = 86_400        # 24 hours for agent sessions

  class << self
    # Start tool execution workflow
    #
    # @param tool [Tool] Tool to execute
    # @param parameters [Hash] Tool parameters
    # @param project [Project, nil] Project context
    # @param timeout [Integer] Execution timeout in seconds
    # @return [Hash] { ok: true/false, workflow_id:, run_id:, handle: }
    def start_tool_execution(tool:, parameters: {}, project: nil, timeout: 300)
      workflow_id = "tool-execution-#{tool.id}-#{SecureRandom.hex(8)}"

      TemporalService.start_workflow(
        workflow,
        {
          strategy_type: "tool_execution",
          image: tool.docker_image,
          strategy_input: {
            tool_id: tool.id,
            parameters: parameters,
            project_id: project&.id,
            timeout: timeout
          }
        },
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
        workflow,
        {
          strategy_type: "tool_execution",
          image: tool.docker_image,
          strategy_input: {
            tool_id: tool.id,
            parameters: parameters,
            project_id: project&.id,
            timeout: timeout
          }
        }
      )
    end

    # Start agent authentication workflow
    #
    # @param session [TerminalSession] Terminal session
    # @return [Hash] { ok: true/false, workflow_id:, run_id:, handle: }
    def start_agent_auth(session:)
      workflow_id = "agent-auth-#{session.id}"

      TemporalService.start_workflow(
        workflow,
        {
          strategy_type: "agent_auth",
          image: resolve_agent_image(session.agent_type),
          strategy_input: {
            user_id: session.user_id,
            agent_type: session.agent_type,
            session_id: session.id,
            route_token: session.route_token
          }
        },
        id: workflow_id,
        execution_timeout: AGENT_WORKFLOW_TIMEOUT
      )
    end

    # Start agent session workflow
    #
    # @param session [TerminalSession] Terminal session
    # @param credential [AgentCredential, nil] Credential to load
    # @return [Hash] { ok: true/false, workflow_id:, run_id:, handle: }
    def start_agent_session(session:, credential: nil)
      workflow_id = "agent-session-#{session.id}"

      TemporalService.start_workflow(
        workflow,
        {
          strategy_type: "agent_session",
          image: resolve_agent_image(session.agent_type),
          strategy_input: {
            user_id: session.user_id,
            agent_type: session.agent_type,
            session_id: session.id,
            route_token: session.route_token,
            credential_id: credential&.id
          }
        },
        id: workflow_id,
        execution_timeout: AGENT_WORKFLOW_TIMEOUT
      )
    end

    # Signal workflow to finish
    #
    # @param workflow_id [String] Workflow ID
    # @param signal [Symbol] Signal name (:container_finished, :container_cancelled)
    # @return [Hash] { ok: true/false, error: }
    def signal_workflow(workflow_id, signal: :container_finished)
      TemporalService.send_signal(workflow_id, signal)
    end

    # Cancel workflow
    #
    # @param workflow_id [String] Workflow ID
    # @return [Hash] { ok: true/false, error: }
    def cancel_workflow(workflow_id)
      TemporalService.cancel_workflow(workflow_id)
    end

    private

    def workflow
      @workflow ||= WorkflowService.unified_container_workflow
    end

    def resolve_agent_image(agent_type)
      ContainerStrategies::AgentAuthStrategy::AGENT_IMAGES.fetch(agent_type) do
        raise ArgumentError, "Unknown agent type: #{agent_type}"
      end
    end
  end
end
