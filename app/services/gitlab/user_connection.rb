# frozen_string_literal: true

module Gitlab
  # A user's own GitLab account, connected through the deployment's GitLab OAuth app
  # and stored as an OauthCredential owned by the user
  # (docs/design/gitlab-user-identity.md §2.2, §4.1).
  module UserConnection
    PROVIDER = OauthCredential::GITLAB_PROVIDER
    LABEL = "GitLab"
    IDENTITY_TTL = 24.hours
    METADATA_KEY = "gitlab_user"

    module_function

    def configured?
      AppConfig.oauth_enabled?
    end

    # The endpoints and issuer follow GITLAB_ENDPOINT (Oauth::Providers#config merges them).
    def endpoints
      base = Host.web_base
      { issuer: base, authorization_endpoint: "#{base}/oauth/authorize", token_endpoint: "#{base}/oauth/token" }
    end

    # Called by the OAuth callback right after the token is stored. A failed lookup never
    # destroys the credential: the stored identity is cleared so the new token is not
    # paired with the previous account's, and identity_for refetches it.
    def record_identity!(credential)
      store_identity!(credential, UserTokenService.new.user(credential.access_token))
    rescue UserTokenService::Error
      credential.update!(metadata: credential.metadata.to_h.except(METADATA_KEY))
      raise ::Oauth::TokenExchangeError, "gitlab identity unavailable"
    end

    # { "id", "username", "name", "avatar_url", "commit_email" } for a connected credential,
    # refetched when older than IDENTITY_TTL.
    def identity_for(credential)
      stored = credential.metadata.to_h[METADATA_KEY]
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

    # Only a grant of the instance GITLAB_ENDPOINT names now is revoked there. One from a
    # previous endpoint is deleted without a request: its token would go to the wrong host.
    def disconnect!(user)
      OauthCredential.gitlab_connections_of(user).each do |credential|
        revoke_grant(credential)
        credential.destroy!
      end
      OauthCredential.for_owner(user).on_other_gitlab_instance.destroy_all
      ActAsConsent.where(user_id: user.id, provider: PROVIDER).delete_all
    end

    def store_identity!(credential, profile)
      identity = {
        "id" => profile[:id], "username" => profile[:username], "name" => profile[:name],
        "avatar_url" => profile[:avatar_url], "commit_email" => profile[:commit_email],
        "fetched_at" => Time.current.iso8601
      }
      credential.update!(metadata: credential.metadata.to_h.merge(METADATA_KEY => identity))
      identity
    end

    def revoke_grant(credential)
      UserTokenService.new.revoke(credential.access_token)
    rescue UserTokenService::Error, Encryptable::DecryptionError => e
      Rails.logger.warn("[Gitlab::UserConnection] could not revoke the grant: #{e.class}")
    end
  end
end
