# frozen_string_literal: true

# Start Authentication Terminal Activity
# Starts a Docker container with agent CLI and ttyd web terminal
#
# Input: { terminal_session_id:, user_id:, agent_type: }
# Returns: { container_id: string }

module Activities
  class StartAuthTerminalActivity < Base
    def run(input)
      session = TerminalSession.find(input.terminal_session_id)

      # Start container via ContainerService
      # Use session's route_token for URL routing
      result = ContainerService.start_auth_container(
        input.user_id,
        input.agent_type,
        session_id: session.id,
        route_token: session.route_token
      )

      # Update session with container info
      # websocket_url is derived from route_token in serializer
      session.update!(container_id: result[:container_id])
      session.mark_running!

      result
    rescue StandardError => e
      session&.update!(error_message: "Failed to start container: #{e.message}")
      session&.fail! if session&.may_fail?
      raise TemporalExceptions.wrap(e, retryable: false)
    end
  end
end
