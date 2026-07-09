# frozen_string_literal: true

# Activities::Oauth::RefreshExpiringTokensActivity
# Proactively refreshes OAuth credentials (integrations + MCP servers) nearing
# expiry, driven by Workflows::OauthTokenRefreshWorkflow on a */5 Temporal
# schedule (oauth-unification §4.5). Per-record rescue so one bad credential never
# fails the batch; refresh runs under a row lock via Oauth::TokenService.
module Activities
  module Oauth
    class RefreshExpiringTokensActivity < ::Activities::Base
      REFRESH_WINDOW = 15.minutes

      def run(_input = nil)
        refreshed = 0
        not_needed = 0
        errors = 0

        ::OauthCredential.refresh_due(REFRESH_WINDOW).find_each do |cred|
          case ::Oauth::TokenService.refresh_credential(cred)
          when :refreshed
            refreshed += 1
          when :error
            errors += 1
            log(:warn, "oauth_credential #{cred.id} (#{cred.provider}) refresh error: #{cred.refresh_error}")
          else
            not_needed += 1
          end
        rescue StandardError => e
          errors += 1
          log(:warn, "oauth_credential #{cred.id} refresh raised: #{e.class}: #{e.message}")
        end

        log(:info, "oauth token refresh sweep: refreshed=#{refreshed} not_needed=#{not_needed} errors=#{errors}")
        { refreshed: refreshed, not_needed: not_needed, errors: errors }
      end
    end
  end
end
