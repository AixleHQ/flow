# frozen_string_literal: true

module Linear
  # What a connection's requests carry. An API key is sent as it is, with no
  # scheme. An OAuth grant's access token lasts a day and is renewed with the
  # refresh token, under a row lock: Linear rotates the refresh token on every
  # use, so two processes refreshing at once would leave one holding a retired one.
  class Credential
    SKEW = 5.minutes
    REAUTHORIZE = "Linear no longer accepts this connection's authorization. Reconnect Linear."

    def initialize(integration)
      @integration = integration
    end

    def authorization_headers
      return { "Authorization" => api_key } if api_key_mode?

      { "Authorization" => "Bearer #{access_token}" }
    end

    # The credential was refused: renew it, unless another process already has.
    # An API key cannot be renewed.
    def invalidate!
      raise Trackers::Error.new("Linear rejected this connection's API key", code: "not_authorized") if api_key_mode?

      @used = renew(refused: @used)
    end

    private

    def api_key_mode?
      @integration.settings.to_h["auth_mode"] == "api_key"
    end

    def api_key
      @integration.credentials_data["api_key"].presence ||
        raise(Trackers::Error.new("This connection has no API key", code: "not_configured"))
    end

    def access_token
      data = @integration.credentials_data
      @used = fresh?(data) ? data["access_token"] : renew
    end

    def renew(refused: nil)
      @integration.with_lock do
        data = @integration.credentials_data
        next data["access_token"] if fresh?(data) && data["access_token"] != refused

        @integration.credentials_data = data.merge(Oauth.refresh(data["refresh_token"]))
        @integration.save!
        @integration.credentials_data["access_token"]
      end
    rescue Trackers::Error => e
      revoke!(e) if e.code == "not_authorized"
      raise
    end

    # A grant from before Linear's refresh tokens has no expiry and no refresh token.
    def fresh?(data)
      return false if data["access_token"].blank?
      return data["refresh_token"].blank? if data["expires_at"].blank?

      Time.zone.parse(data["expires_at"]) > SKEW.from_now
    end

    # Outside the lock's transaction, which the refusal rolled back.
    def revoke!(error)
      Rails.logger.warn("[Linear::Credential] integration #{@integration.id} not authorized: #{error.message}")
      @integration.update_columns(status: "error", settings: @integration.settings.to_h.merge("error" => REAUTHORIZE),
                                  updated_at: Time.current)
    end
  end
end
