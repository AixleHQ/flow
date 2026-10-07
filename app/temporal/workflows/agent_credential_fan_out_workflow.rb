# frozen_string_literal: true

module Workflows
  # Started by AgentCredential#fan_out_rotation whenever a write replaces a refresh token.
  class AgentCredentialFanOutWorkflow < Base
    def run(input = nil)
      execute_activity(
        activities.agent_credentials_fan_out_activity,
        { credential_id: input&.credential_id, origin_session_id: input&.origin_session_id },
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
      )
    end
  end
end
