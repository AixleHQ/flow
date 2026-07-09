# frozen_string_literal: true

module Workflows
  # OauthTokenRefreshWorkflow — proactively refreshes OAuth credentials (integrations
  # + MCP servers) nearing expiry (oauth-unification §4.5). Wired into
  # app/temporal/schedules.yml (*/5, overlap skip). The agent-CLI equivalent is
  # AgentTokenRefreshWorkflow; the two target different stores (OauthCredential vs
  # AgentCredential) and run independently.
  class OauthTokenRefreshWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.oauth_refresh_expiring_tokens_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
