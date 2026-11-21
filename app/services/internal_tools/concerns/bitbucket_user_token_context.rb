# frozen_string_literal: true

module InternalTools
  module Concerns
    # Bitbucket's part of the user-token steps (docs/design/bitbucket-user-identity.md
    # §4.2; the shared steps are in UserTokenContext). Bitbucket cannot narrow a token to
    # repositories, so the tool hands out the person's own OAuth token and checks, with
    # that token, which of the session's repositories the person can write to.
    #
    # It follows GitLab's refresh rule: a person has one token for all their sessions and
    # it is not known that a refresh leaves the old access token valid, so the tool
    # refreshes only within Oauth::TokenService::REFRESH_SKEW of expiry, as the platform's
    # sweep does, and reports the expiry less that skew.
    module BitbucketUserTokenContext
      extend ActiveSupport::Concern
      include UserTokenContext

      SCOPES = %w[account email repository repository:write pullrequest pullrequest:write].freeze
      GIT_USERNAME = "x-token-auth"
      NOTE = "Use the token only in the command that needs it. Do not echo it, write it to a file, or paste it " \
             "anywhere. Ask again when it expires, or when Bitbucket refuses it with 401. The token is not limited " \
             "to these repositories: it can do whatever this person can on Bitbucket, so use it for these " \
             "repositories only. Prefer git over HTTPS to the REST API: REST calls with it spend this person's own " \
             "Bitbucket request quota."
      UNAVAILABLE = "Connecting Bitbucket accounts is not configured on this installation."
      NO_REPOSITORIES = "This session has no Bitbucket repositories on an active Bitbucket connection."
      NO_CONFIRMED_EMAIL = "Bitbucket did not return this account's identity, or the account has no confirmed " \
                           "primary email address, which commits are made with. The person needs a confirmed " \
                           "primary email on Bitbucket; then they reconnect the account under " \
                           "Profile → Connected accounts."
      WRITE_LEVELS = %w[admin write].freeze
      UNCHECKED_REASON = "Bitbucket's permission list for the workspace was too long to read in full"

      private

      def issue_bitbucket_tokens(user:, consent_scope:)
        issue_user_tokens(user: user, consent_scope: consent_scope)
      end

      def provider_label = "Bitbucket"
      def provider_name = Bitbucket::UserConnection::PROVIDER
      def live_connection_of(user) = OauthCredential.live_bitbucket_connection_of(user)
      def no_repositories_message = NO_REPOSITORIES
      def token_skew = Oauth::TokenService::REFRESH_SKEW

      def identity_of(credential) = Bitbucket::UserConnection.identity_for(credential)

      def identity_usable?(identity)
        identity.present? && identity["id"].present? && identity["nickname"].present? &&
          Bitbucket::UserConnection.commit_email(identity).present?
      end

      # Besides a failed lookup, a confirmed address is the one thing Bitbucket's identity can lack.
      def no_identity_message = NO_CONFIRMED_EMAIL

      # [repositories to cover, skipped entries]. Both integration modes (the Forge app and
      # a token) qualify; the integration's own credential is never used. One whose
      # integration is not active is skipped.
      def collect_repositories
        bitbucket = session.repositories.includes(:integration).select { |repo| repo.integration&.bitbucket? }
        covered, skipped = bitbucket.partition { |repo| repo.integration.active? }
        skipped_entries = skipped.map do |repo|
          { repository: repo.full_name, reason: "its Bitbucket connection is not active" }
        end
        [ covered.sort_by(&:id), skipped_entries ]
      end

      # The person's own token, once for all the repositories they can write to.
      def mint_tokens!(user, credential, user_token, repositories, _identity)
        covered, skipped = check_coverage!(user, credential, user_token, repositories)
        raise UserTokenContext::Refusal, refusal_message(user, skipped) if covered.empty?

        expires_at = reported_expiry(credential)
        record_issuance!(user: user, credential: credential, token: user_token,
                         target_login: URI.parse(Bitbucket::AppConfig::WEB_HOST).host.to_s,
                         repositories: covered, expires_at: expires_at)
        token = { token: user_token, host: Bitbucket::AppConfig::WEB_HOST, scopes: SCOPES, git_username: GIT_USERNAME,
                  api_url: "#{Bitbucket::AppConfig::API_HOST}#{Bitbucket::Client::BASE_PATH}",
                  repositories: covered.map(&:full_name), expires_at: expires_at&.iso8601 }
        [ [ token ], skipped ]
      end

      # [covered repositories, skipped entries]: `write` or `admin` covers one. A repository
      # the person has no permission on (a missing entry) is one they cannot push to; one
      # Bitbucket's permission list was too long to read in full is one that could not be
      # checked, which is said as such.
      def check_coverage!(user, credential, user_token, repositories)
        answer = bitbucket_api(user_token).repository_permissions(repositories.map(&:full_name))
        covered, rest = repositories.partition { |repo| WRITE_LEVELS.include?(answer[:levels][repo.full_name]) }
        [ covered, rest.map { |repo| skipped_entry(user, repo, answer[:unchecked].include?(repo.full_name)) } ]
      rescue Bitbucket::Error::NotAuthorized
        credential.mark_refresh_error!("Bitbucket no longer accepts this user token")
        raise UserTokenContext::Refusal, reconnect_message(user)
      rescue Bitbucket::Error
        raise UserTokenContext::Refusal, "Bitbucket is unavailable right now. Retry in a moment."
      end

      def skipped_entry(user, repo, unchecked)
        reason = unchecked ? UNCHECKED_REASON : "#{user.name} cannot push to it"
        { repository: repo.full_name, reason: reason }
      end

      # Why nothing is covered: the repositories the person cannot push to, and those that
      # could not be checked, each said for what they are.
      def refusal_message(user, skipped)
        unchecked, refused = skipped.partition { |entry| entry[:reason] == UNCHECKED_REASON }
        parts = []
        parts << "#{user.name} cannot push to #{refused.pluck(:repository).join(', ')} on Bitbucket." if refused.any?
        parts << "Could not check whether #{user.name} can push to #{unchecked.pluck(:repository).join(', ')}: " \
                 "#{UNCHECKED_REASON}." if unchecked.any?
        parts.join(" ")
      end

      def bitbucket_api(user_token)
        Bitbucket::Api.new(Bitbucket::Credential.new(token: user_token, kind: :access_token))
      end

      # When to ask again: the stored expiry less the refresh skew, since a refresh may end
      # the old access token (design §2.4).
      def reported_expiry(credential)
        credential.expires_at && (credential.expires_at - Oauth::TokenService::REFRESH_SKEW)
      end

      def result(user, identity, tokens, skipped)
        {
          user: { id: user.id, name: user.name },
          identity: { login: identity["nickname"], bitbucket_uuid: identity["id"],
                      name: identity["name"].presence || identity["nickname"],
                      email: Bitbucket::UserConnection.commit_email(identity) },
          tokens: tokens,
          skipped: skipped,
          note: NOTE
        }
      end
    end
  end
end
