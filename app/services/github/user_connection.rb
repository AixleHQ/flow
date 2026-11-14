# frozen_string_literal: true

module Github
  # A user's own GitHub account, connected through the App's user OAuth flow and
  # stored as an OauthCredential owned by the user
  # (docs/design/github-user-identity.md §2.1, §4.1).
  module UserConnection
    PROVIDER = OauthCredential::GITHUB_PROVIDER
    LABEL = "GitHub"
    IDENTITY_TTL = 24.hours

    module_function

    def configured?
      Settings.github.client_id.present? && Settings.github.client_secret.present?
    end

    # Called by the OAuth callback right after the token is stored. A connection
    # without an identity is useless, but a failed lookup never destroys the credential
    # (a reconnect would lose a working connection): the stored identity is cleared so the
    # new token is not paired with the previous account's, and identity_for refetches it.
    def record_identity!(credential)
      profile = UserTokenService.new.user(credential.access_token)
      store_identity!(credential, profile)
    rescue UserTokenService::Error
      credential.update!(metadata: credential.metadata.to_h.except("github_user"))
      raise Oauth::TokenExchangeError, "github identity unavailable"
    end

    # { "id", "login", "name", "avatar_url" } for a connected credential. Refetched
    # when older than IDENTITY_TTL so a renamed account does not commit under its old login.
    def identity_for(credential)
      stored = credential.metadata.to_h["github_user"]
      fetched_at = stored && Time.zone.parse(stored["fetched_at"].to_s)
      return stored if stored && fetched_at && fetched_at > IDENTITY_TTL.ago

      store_identity!(credential, UserTokenService.new.user(credential.access_token))
    rescue UserTokenService::Error
      stored
    end

    # The person's connection, a revoked one included, or nil.
    def latest_connection_of(user)
      OauthCredential.latest_github_connection_of(user)
    end

    def disconnect!(user)
      OauthCredential.github_connections_of(user).each do |credential|
        revoke_grant(credential)
        credential.destroy!
      end
      ActAsConsent.where(user_id: user.id, provider: PROVIDER).delete_all
    end

    def store_identity!(credential, profile)
      identity = {
        "id" => profile[:id], "login" => profile[:login], "name" => profile[:name],
        "avatar_url" => profile[:avatar_url], "fetched_at" => Time.current.iso8601
      }
      credential.update!(metadata: credential.metadata.to_h.merge("github_user" => identity))
      identity
    end

    def revoke_grant(credential)
      UserTokenService.new.revoke_grant(credential.access_token)
    rescue UserTokenService::Error, Encryptable::DecryptionError => e
      Rails.logger.warn("[Github::UserConnection] could not revoke the grant: #{e.class}")
    end
  end
end
