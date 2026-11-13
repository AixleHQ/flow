# frozen_string_literal: true

module InternalTools
  module Concerns
    # GitLab's part of the user-token steps (docs/design/gitlab-user-identity.md §4.2;
    # the shared steps are in UserTokenContext). GitLab cannot narrow a token to
    # repositories, so the tool hands out the person's own OAuth token (refreshed when
    # little life remains) and checks, with that token, which of the session's
    # repositories the person can push to.
    module GitlabUserTokenContext
      extend ActiveSupport::Concern
      include UserTokenContext

      # A token handed out has at least this long to live; the platform refreshes at
      # Oauth::TokenService::REFRESH_SKEW, so the agent has the difference to work with.
      MIN_LIFETIME = 30.minutes
      SCOPES = %w[api].freeze
      NOTE = "Use the token only in the command that needs it. Do not echo it, write it to a file, or paste it " \
             "anywhere. Ask again when it expires. The token is not limited to these repositories: it can do " \
             "whatever this person can on GitLab, so use it for these repositories only."
      UNAVAILABLE = "Connecting GitLab accounts is not configured on this installation."
      NO_REPOSITORIES = "This session has no GitLab repositories on an active GitLab connection."

      private

      def issue_gitlab_tokens(user:, consent_scope:)
        issue_user_tokens(user: user, consent_scope: consent_scope)
      end

      def provider_label = "GitLab"
      def provider_name = Gitlab::UserConnection::PROVIDER
      def live_connection_of(user) = OauthCredential.live_gitlab_connection_of(user)
      def no_repositories_message = NO_REPOSITORIES
      def token_skew = MIN_LIFETIME

      def identity_of(credential) = Gitlab::UserConnection.identity_for(credential)

      def identity_usable?(identity)
        identity.present? && identity["username"].present? && identity["id"].present?
      end

      # [repositories to cover, skipped entries]. Both integration auth modes qualify; the
      # integration's own token is never used. One whose integration is not active is skipped.
      def collect_repositories
        gitlab = session.repositories.includes(:integration).select { |repo| repo.integration&.gitlab? }
        covered, skipped = gitlab.partition { |repo| repo.integration.active? }
        skipped_entries = skipped.map { |repo| { repository: repo.full_name, reason: "its GitLab connection is not active" } }
        [ covered.sort_by(&:id), skipped_entries ]
      end

      # The person's own token, once for all the repositories they can push to.
      def mint_tokens!(user, credential, user_token, repositories, identity)
        covered, skipped = check_coverage!(user, credential, user_token, repositories, identity)
        if covered.empty?
          raise Refusal, "#{user.name} cannot push to #{repositories.map(&:full_name).join(', ')} on GitLab."
        end

        expires_at = reported_expiry(credential)
        record_issuance!(user: user, credential: credential, token: user_token, target_login: gitlab_host_name,
                         repositories: covered, expires_at: expires_at)
        token = { token: user_token, host: Gitlab::Host.web_base, scopes: SCOPES, git_username: "oauth2",
                  api_url: Gitlab::Host.api_endpoint, repositories: covered.map(&:full_name),
                  expires_at: expires_at&.iso8601 }
        [ [ token ], skipped ]
      end

      # [covered repositories, skipped entries]: Developer access or more covers one.
      def check_coverage!(user, credential, user_token, repositories, identity)
        service = Gitlab::UserTokenService.new
        covered, skipped = repositories.partition do |repo|
          access_level(service, user_token, repo, identity).to_i >= Gitlab::UserTokenService::DEVELOPER
        end
        [ covered, skipped.map { |repo| { repository: repo.full_name, reason: "#{user.name} cannot push to it" } } ]
      rescue Gitlab::UserTokenService::InvalidToken
        credential.mark_refresh_error!("GitLab no longer accepts this user token")
        raise Refusal, reconnect_message(user)
      rescue Gitlab::UserTokenService::Unavailable
        raise Refusal, "GitLab is unavailable right now. Retry in a moment."
      end

      # A repository GitLab refuses to show the person (403) is one they cannot push to.
      def access_level(service, user_token, repo, identity)
        service.project_access(user_token, repo.full_name, user_id: identity["id"])
      rescue Gitlab::UserTokenService::Forbidden
        nil
      end

      # When to ask again: the stored expiry less the refresh skew, since a refresh issues a
      # new access token and GitLab may revoke the old one at that moment.
      def reported_expiry(credential)
        credential.expires_at && (credential.expires_at - Oauth::TokenService::REFRESH_SKEW)
      end

      def gitlab_host_name
        URI.parse(Gitlab::Host.web_base).host.to_s
      end

      def result(user, identity, tokens, skipped)
        {
          user: { id: user.id, name: user.name },
          identity: { login: identity["username"], gitlab_id: identity["id"],
                      name: identity["name"].presence || identity["username"],
                      email: Gitlab::UserConnection.commit_email(identity) },
          tokens: tokens,
          skipped: skipped,
          note: NOTE
        }
      end
    end
  end
end
