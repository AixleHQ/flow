# frozen_string_literal: true

# Stop Container Activity
# Stops and removes the Docker container, cleaning up resources
# Also updates the terminal session state to 'stopped'
#
# Input: { container_id:, terminal_session_id: (optional) }
# Returns: { status: :stopped }

module Activities
  class StopContainerActivity < Base
    def run(input)
      ContainerService.stop_container(input.container_id)

      # Update session state if session_id provided
      if input.terminal_session_id.present?
        session = TerminalSession.find_by(id: input.terminal_session_id)
        session&.stop! if session&.may_stop?
      end

      { status: :stopped }
    rescue StandardError => e
      log(:error, "Failed to stop container #{input.container_id}: #{e.message}")
      # Don't fail the workflow if cleanup fails, just log it
      { status: :error, message: e.message }
    end
  end
end
