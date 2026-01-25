# frozen_string_literal: true

# Stop Container Activity
# Stops and removes the Docker container, cleaning up resources
#
# Input: { container_id: }
# Returns: { status: :stopped }

module Activities
  class StopContainerActivity < Base
    def run(input)
      ContainerService.stop_container(input.container_id)

      { status: :stopped }
    rescue StandardError => e
      log(:error, "Failed to stop container #{input.container_id}: #{e.message}")
      # Don't fail the workflow if cleanup fails, just log it
      { status: :error, message: e.message }
    end
  end
end
