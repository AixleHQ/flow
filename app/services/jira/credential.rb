# frozen_string_literal: true

module Jira
  # The bearer token a connection's requests carry, kept in its encrypted
  # credentials and renewed per auth mode: a 3LO grant refreshes, a service
  # account asks for a new client-credentials token.
  #
  # Renewal happens under a row lock. Atlassian rotates the 3LO refresh token on
  # every use, so two processes refreshing at once would leave one of them
  # holding a token Atlassian has already retired.
  class Credential
    SKEW = 5.minutes
    REAUTHORIZE = "Atlassian no longer accepts this connection's authorization. Reconnect Jira."

    def initialize(integration)
      @integration = integration
    end

    def authorization_headers
      { "Authorization" => "Bearer #{access_token}" }
    end

    def access_token
      data = @integration.credentials_data
      @used = fresh?(data) ? data["access_token"] : renew
    end

    # The token was refused: renew it, unless another process already has.
    def invalidate!
      @used = renew(refused: @used)
    end

    private

    def renew(refused: nil)
      return renew_unsaved(refused) unless @integration.persisted?

      @integration.with_lock do
        data = @integration.credentials_data
        next data["access_token"] if fresh?(data) && data["access_token"] != refused

        store(data, grant(data))
      end
    rescue Error => e
      revoke!(e) if e.code == "not_authorized"
      raise
    end

    # A connection being set up is not saved yet; nothing else can hold it.
    def renew_unsaved(refused)
      data = @integration.credentials_data
      return data["access_token"] if fresh?(data) && data["access_token"] != refused

      @integration.credentials_data = data.merge(grant(data))
      @integration.credentials_data["access_token"]
    end

    def grant(data)
      if @integration.settings.to_h["auth_mode"] == "service_account"
        Oauth.client_credentials(client_id: data["client_id"], client_secret: data["client_secret"])
      else
        Oauth.refresh(data["refresh_token"])
      end
    end

    def store(data, token)
      @integration.credentials_data = data.merge(token)
      @integration.save!
      token["access_token"]
    end

    def fresh?(data)
      data["access_token"].present? && data["expires_at"].present? && Time.zone.parse(data["expires_at"]) > SKEW.from_now
    end

    # Outside the lock's transaction, which the refusal rolled back.
    def revoke!(error)
      return unless @integration.persisted?

      Rails.logger.warn("[Jira::Credential] integration #{@integration.id} not authorized: #{error.message}")
      @integration.update_columns(status: "error", settings: @integration.settings.to_h.merge("error" => REAUTHORIZE),
                                  updated_at: Time.current)
    end
  end
end
