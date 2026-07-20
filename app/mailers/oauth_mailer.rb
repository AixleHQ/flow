# frozen_string_literal: true

# Refresh-failure notifications for OAuth credentials (oauth-unification §4.6).
class OauthMailer < ApplicationMailer
  # Sent once when a credential is escalated to status:error after
  # MAX_REFRESH_FAILURES consecutive refresh failures — the owner must reconnect.
  # Gated to User owners by the caller (OauthCredential#notify_refresh_failure).
  def refresh_failed(credential)
    @provider = credential.provider
    @connect_url =
      if credential.mcp_server_id
        oauth_mcp_connect_url(mcp_server_id: credential.mcp_server_id,
                              host: Settings.domain, protocol: Settings.protocol)
      end

    mail(to: credential.owner.email, subject: "Action needed: reconnect #{@provider}")
  end
end
