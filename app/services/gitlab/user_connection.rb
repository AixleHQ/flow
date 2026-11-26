# frozen_string_literal: true

module Gitlab
  # A user's own GitLab account, connected through the deployment's GitLab OAuth app
  # and stored as an OauthCredential owned by the user
  # (docs/design/gitlab-user-identity.md §2.2, §4.1).
  module UserConnection
    PROVIDER = OauthCredential::GITLAB_PROVIDER
    LABEL = "GitLab"
    IDENTITY_TTL = 24.hours

    module_function

    # Where this account's identity sits in the credential's metadata (the model owns it).
    def metadata_key
      OauthCredential::IDENTITY_FIELDS.dig(PROVIDER, :metadata_key)
    end

    def configured?
      AppConfig.oauth_enabled?
    end

    # The endpoints and issuer follow GITLAB_ENDPOINT (Oauth::Providers#config merges them).
    def endpoints
      base = Host.web_base
      { issuer: base, authorization_endpoint: "#{base}/oauth/authorize", token_endpoint: "#{base}/oauth/token",
        revocation_endpoint: "#{base}/oauth/revoke" }
    end

    # Called by the OAuth callback with the new access token, before the credential is
    # stored: the identity to store with it. A failed lookup fails the connection, so
    # nothing is stored and a previous credential stays as it was.
    def fetch_identity(access_token)
      build_identity(UserTokenService.new.user(access_token))
    rescue UserTokenService::Error
      raise ::Oauth::TokenExchangeError, "gitlab identity unavailable"
    end

    # { "id", "username", "name", "avatar_url", "commit_email" } for a connected credential,
    # refetched when older than IDENTITY_TTL.
    def identity_for(credential)
      stored = credential.metadata.to_h[metadata_key]
      fetched_at = stored && Time.zone.parse(stored["fetched_at"].to_s)
      return stored if stored && fetched_at && fetched_at > IDENTITY_TTL.ago

      store_identity!(credential, UserTokenService.new.user(credential.access_token))
    rescue UserTokenService::Error
      stored
    end

    # The address GitLab itself commits with for this account.
    def commit_email(identity)
      identity["commit_email"].presence ||
        "#{identity['id']}-#{identity['username']}@users.noreply.#{URI.parse(Host.web_base).host}"
    end

    # The person's connection on this instance, a revoked one included, or nil.
    def latest_connection_of(user)
      OauthCredential.latest_gitlab_connection_of(user)
    end

    # Only a grant of the client configured now is revoked there. One of another client (a
    # previous endpoint or client id) is deleted without a request: its token would go to
    # the wrong host, or be refused.
    def disconnect!(user)
      OauthCredential.gitlab_connections_of(user).each do |credential|
        revoke_grant(credential)
        credential.destroy!
      end
      OauthCredential.all_connections_of(user, PROVIDER).destroy_all
      ActAsConsent.where(user_id: user.id, provider: PROVIDER).delete_all
    end

    def build_identity(profile)
      {
        "id" => profile[:id], "username" => profile[:username], "name" => profile[:name],
        "avatar_url" => profile[:avatar_url], "commit_email" => profile[:commit_email],
        "fetched_at" => Time.current.iso8601
      }
    end

    def store_identity!(credential, profile)
      identity = build_identity(profile)
      credential.update!(metadata: credential.metadata.to_h.merge(metadata_key => identity))
      identity
    end

    def revoke_grant(credential)
      ::Oauth::TokenService.revoke!(credential)
    rescue ::Oauth::RevocationError, Encryptable::DecryptionError => e
      Rails.logger.warn("[Gitlab::UserConnection] could not revoke the grant: #{e.class}")
    end
  end
end
