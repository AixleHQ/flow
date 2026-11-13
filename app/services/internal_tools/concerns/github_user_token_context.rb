# frozen_string_literal: true

module InternalTools
  module Concerns
    # GitHub's part of the user-token steps (docs/design/github-user-identity.md §4.3;
    # the shared steps are in UserTokenContext). The token is minted per repository
    # owner, limited to the session's repositories and to the permissions below.
    module GithubUserTokenContext
      extend ActiveSupport::Concern
      include UserTokenContext

      PERMISSIONS = { "contents" => "write", "pull_requests" => "write" }.freeze
      NOTE = "Use the token only in the command that needs it. Do not echo it, write it to a file, or paste it " \
             "anywhere. Ask again when it expires."
      UNAVAILABLE = "Connecting GitHub accounts is not configured on this installation."
      NO_REPOSITORIES = "This session has no GitHub repositories connected through the GitHub App."

      private

      def issue_github_tokens(user:, consent_scope:)
        issue_user_tokens(user: user, consent_scope: consent_scope)
      end

      def provider_label = "GitHub"
      def provider_name = Github::UserConnection::PROVIDER
      def live_connection_of(user) = OauthCredential.live_github_connection_of(user)
      def no_repositories_message = NO_REPOSITORIES
      def token_skew = Oauth::TokenService::PRE_START_SKEW

      def identity_of(credential) = Github::UserConnection.identity_for(credential)

      def identity_usable?(identity)
        identity.present? && identity["login"].present? && identity["id"].present?
      end

      # [repositories to cover, skipped entries]. A repository on a personal access
      # token connection is skipped: the scoped-token endpoint needs the App installed.
      def collect_repositories
        github = session.repositories.includes(:integration).select { |repo| repo.integration&.github? }
        covered, skipped = github.partition { |repo| repo.integration.active? && repo.integration.github_app? }
        skipped_entries = skipped.map do |repo|
          { repository: repo.full_name, reason: "not connected through the GitHub App" }
        end
        [ covered.sort_by(&:id), skipped_entries ]
      end

      def mint_tokens!(user, credential, user_token, repositories, identity)
        tokens = repositories.group_by(&:owner_name).map do |owner, repos|
          mint_token!(user, credential, user_token, owner, repos, identity)
        end
        [ tokens, [] ]
      end

      def mint_token!(user, credential, user_token, owner, repositories, identity)
        names = repositories.map { |repo| repo.full_name.split("/", 2).last }
        minted = Github::UserTokenService.new.scoped_token(user_token: user_token, target: owner,
                                                           repositories: names, permissions: PERMISSIONS)
        record_issuance!(user: user, credential: credential, token: minted[:token], target_login: owner,
                         repositories: repositories, expires_at: minted[:expires_at],
                         token_last_eight: minted[:token_last_eight])
        { token: minted[:token], owner: owner, repositories: repositories.map(&:full_name),
          permissions: PERMISSIONS, expires_at: minted[:expires_at]&.iso8601 }
      rescue Github::UserTokenService::InvalidToken
        credential.mark_refresh_error!("GitHub no longer accepts this user token")
        raise Refusal, reconnect_message(user)
      rescue Github::UserTokenService::Forbidden
        raise Refusal, "GitHub refused access to #{repositories.map(&:full_name).join(', ')} for " \
                       "#{identity&.dig('login') || user.name}: the user or the App has no access there."
      rescue Github::UserTokenService::Unavailable
        raise Refusal, "GitHub is unavailable right now. Retry in a moment."
      end

      def result(user, identity, tokens, skipped)
        login = identity&.dig("login")
        github_id = identity&.dig("id")
        {
          user: { id: user.id, name: user.name },
          identity: { login: login, github_id: github_id, name: identity&.dig("name").presence || login,
                      email: "#{github_id}+#{login}@users.noreply.github.com" },
          tokens: tokens,
          skipped: skipped,
          note: NOTE
        }
      end
    end
  end
end
