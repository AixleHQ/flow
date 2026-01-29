# frozen_string_literal: true

# Collect Artifacts Activity
# Extracts authentication artifacts from container after user completes auth
# Uses AgentCredentialsService for agent-specific credential extraction
#
# Input: { terminal_session_id:, container_id:, agent_type: }
# Returns: { credential_id: integer }

module Activities
  class CollectArtifactsActivity < Base
    def run(input)
      session = TerminalSession.find(input.terminal_session_id)

      # Use agent-specific service to extract credentials
      service = AgentCredentialsService.for(input.agent_type)

      # Extract and save credentials from container
      credential = service.save_credentials_from_container(session.user, input.container_id)

      # Transfer env var fields from session metadata to credential metadata
      # (e.g., GOOGLE_CLOUD_PROJECT for Gemini CLI)
      if session.metadata.present?
        env_fields = service.adapter.required_env_fields.map { |f| f[:key] }
        env_metadata = session.metadata.slice(*env_fields)
        if env_metadata.present?
          credential.update!(metadata: (credential.metadata || {}).merge(env_metadata))
        end
      end

      # Update session
      session.update!(artifacts_path: credential.id.to_s)
      session.collect!

      { credential_id: credential.id }
      # rescue StandardError => e
      #   Rails.logger.error("[CollectArtifactsActivity] Error: #{e.message}")
      #   session&.update!(error_message: "Failed to collect artifacts: #{e.message}")
      #   session&.fail! if session&.may_fail?
      #   raise TemporalExceptions.wrap(e, retryable: false)
    end
  end
end
