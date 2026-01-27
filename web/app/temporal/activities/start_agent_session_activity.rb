# frozen_string_literal: true

# Start Agent Session Activity
# Starts a Docker container with agent CLI and pre-loaded credentials
#
# Input: { terminal_session_id:, user_id:, agent_type: }
# Returns: { container_id: string }

module Activities
  class StartAgentSessionActivity < Base
    def run(input)
      session = TerminalSession.find(input.terminal_session_id)
      user = User.find(input.user_id)

      # Find credentials for this agent
      credential = user.agent_credentials.find_by(agent_type: input.agent_type)

      # Start container via ContainerService with credentials
      result = ContainerService.start_agent_container(
        input.user_id,
        input.agent_type,
        session_id: session.id,
        route_token: session.route_token,
        credential: credential
      )

      # Update session with container info
      # websocket_url is derived from route_token in serializer
      session.update!(container_id: result[:container_id])
      session.mark_running!

      result
    rescue StandardError => e
      session&.update!(error_message: "Failed to start agent session: #{e.message}")
      session&.fail! if session&.may_fail?
      raise TemporalExceptions.wrap(e, retryable: false)
    end
  end
end
