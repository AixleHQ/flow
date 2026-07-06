# frozen_string_literal: true

# Activities::AgentCredentials::RefreshExpiringTokensActivity
# Proactively refreshes agent-CLI OAuth tokens nearing expiry, driven by
# Workflows::AgentTokenRefreshWorkflow on a */5 Temporal schedule.
# Per-record rescue so one bad credential never fails the batch.
module Activities
  module AgentCredentials
    class RefreshExpiringTokensActivity < ::Activities::Base
      REFRESH_WINDOW = 15.minutes

      def run(_input = nil)
        refreshed = 0
        not_needed = 0
        errors = 0

        ::AgentCredential.refreshable.refresh_due(REFRESH_WINDOW).find_each do |credential|
          result = credential.adapter.refresh!(credential)
          case result[:status]
          when :refreshed
            refreshed += 1
          when :error
            errors += 1
            log(:warn, "credential #{credential.id} (#{credential.agent_type}) refresh error: #{result[:detail]}")
          else
            not_needed += 1
          end
        rescue StandardError => e
          errors += 1
          log(:warn, "credential #{credential.id} refresh raised: #{e.class}: #{e.message}")
        end

        log(:info, "token refresh sweep: refreshed=#{refreshed} not_needed=#{not_needed} errors=#{errors}")
        { refreshed: refreshed, not_needed: not_needed, errors: errors }
      end
    end
  end
end
