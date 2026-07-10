# frozen_string_literal: true

module Workflows
  # AgentTokenRefreshWorkflow — proactively refreshes agent-CLI OAuth tokens
  # nearing expiry. Wired into app/temporal/schedules.yml (*/5, overlap skip).
  class AgentTokenRefreshWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.agent_credentials_refresh_expiring_tokens_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
