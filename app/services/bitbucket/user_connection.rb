# frozen_string_literal: true

module Bitbucket
  # A user's own Bitbucket Cloud account, connected through the deployment's OAuth client
  # and stored as an OauthCredential owned by the user
  # (docs/design/bitbucket-user-identity.md §2.3, §4.1). The calls made with the person's
  # token go through Bitbucket::Api, the one Bitbucket seam.
  module UserConnection
    PROVIDER = OauthCredential::BITBUCKET_PROVIDER
    LABEL = "Bitbucket"
    IDENTITY_TTL = 24.hours

    module_function

    # Where this account's identity sits in the credential's metadata (the model owns it).
    def metadata_key
      OauthCredential::IDENTITY_FIELDS.dig(PROVIDER, :metadata_key)
    end

    def configured?
      AppConfig.oauth_enabled?
    end

    # A client for the person's token. It has no refresher: a 401 is the token being
    # refused, and the caller decides what that means for the connection.
    def api_for(credential)
      api_for_token(credential.access_token)
    end

    def api_for_token(access_token)
      Api.new(Credential.new(token: access_token, kind: :access_token))
    end

    # Called by the OAuth callback with the new access token, before the credential is
    # stored: the identity to store with it. A failed lookup fails the connection, so
    # nothing is stored and a previous credential stays as it was.
    def fetch_identity(access_token)
      build_identity(fetch_profile(access_token))
    rescue Bitbucket::Error
      raise ::Oauth::TokenExchangeError, "bitbucket identity unavailable"
    end

    # { "id", "nickname", "name", "avatar_url", "commit_email" } for a connected credential,
    # refetched when older than IDENTITY_TTL. "id" is the account's UUID.
    def identity_for(credential)
      stored = credential.metadata.to_h[metadata_key]
      fetched_at = stored && Time.zone.parse(stored["fetched_at"].to_s)
      return stored if stored && fetched_at && fetched_at > IDENTITY_TTL.ago

      store_identity!(credential, fetch_profile(credential.access_token))
    rescue Bitbucket::Error
      stored
    end

    # The address commits are made with: the person's primary confirmed address (nil when
    # there is none, and the tool refuses). Bitbucket has no noreply address.
    def commit_email(identity)
      identity["commit_email"].presence
    end

    # The person's connection, a revoked one included, or nil.
    def latest_connection_of(user)
      OauthCredential.latest_bitbucket_connection_of(user)
    end

    # Bitbucket documents no revocation endpoint, so nothing is sent there: the credential
    # (and the refresh token with it) and the person's consents are deleted. An access token
    # already handed out works until it expires, and the authorization stays listed in the
    # person's Atlassian account until they remove it there (design §2.5).
    def disconnect!(user)
      OauthCredential.all_connections_of(user, PROVIDER).destroy_all
      ActAsConsent.where(user_id: user.id, provider: PROVIDER).delete_all
    end

    def fetch_profile(access_token)
      api = api_for_token(access_token)
      profile = api.current_user
      emails = api.user_emails
      primary = emails.find { |entry| entry[:is_primary] && entry[:is_confirmed] }
      profile.merge(commit_email: primary && primary[:email].presence)
    end

    def build_identity(profile)
      {
        "id" => profile[:uuid], "nickname" => profile[:nickname], "name" => profile[:display_name],
        "avatar_url" => profile[:avatar_url], "commit_email" => profile[:commit_email],
        "fetched_at" => Time.current.iso8601
      }
    end

    def store_identity!(credential, profile)
      identity = build_identity(profile)
      credential.update!(metadata: credential.metadata.to_h.merge(metadata_key => identity))
      identity
    end
  end
end
