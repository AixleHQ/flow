# frozen_string_literal: true

module InternalTools
  module Concerns
    # The steps both github_user_token tools share (docs/design/github-user-identity.md
    # §4.3), in order; the first failure answers with an error. A tool names the user
    # it acts for and the consent switch that user must have turned on.
    #
    # Messages never carry a token or a GitHub response body: InternalToolExecutor
    # hands exception messages to the agent.
    module GithubUserTokenContext
      extend ActiveSupport::Concern

      PERMISSIONS = { "contents" => "write", "pull_requests" => "write" }.freeze
      NOTE = "Use the token only in the command that needs it. Do not echo it, write it to a file, or paste it " \
             "anywhere. Ask again when it expires."
      UNAVAILABLE = "Connecting GitHub accounts is not configured on this installation."
      NO_USER = "This session has no user, so there is no one to act as."
      NO_IDENTITY = "GitHub did not return this account's identity. Retry in a moment, or reconnect the account " \
                    "under Profile → Connected accounts."
      NO_PROJECT = "This session has no project."
      NO_REPOSITORIES = "This session has no GitHub repositories connected through the GitHub App."

      class Refusal < StandardError; end

      private

      def issue_github_tokens(user:, consent_scope:)
        raise Refusal, NO_USER if session_user.nil?
        raise Refusal, NO_PROJECT if project.nil?

        check_member!(user)
        credential = connection_for!(user)
        check_consent!(user, consent_scope)
        repositories, skipped = collect_repositories
        raise Refusal, NO_REPOSITORIES if repositories.empty?

        user_token = fresh_user_token!(user, credential)
        identity = Github::UserConnection.identity_for(credential)
        raise Refusal, NO_IDENTITY if identity.blank? || identity["login"].blank? || identity["id"].blank?

        tokens = repositories.group_by(&:owner_name).map do |owner, repos|
          mint_token!(user, credential, user_token, owner, repos, identity)
        end
        raise Refusal, unarmed_message unless Sessions::SecretRegistry.publish!(session)

        success(result(user, identity, tokens, skipped).to_json)
      rescue Refusal => e
        error(e.message)
      end

      def check_member!(user)
        return if user.authenticatable? && project.accessible_by?(user)

        raise Refusal, "#{user.name} is not a member of project #{project.name}."
      end

      def connection_for!(user)
        credential = OauthCredential.live_github_connection_of(user)
        return credential if credential

        raise Refusal, "#{user.name} has not connected a GitHub account. " \
                       "They can connect one under Profile → Connected accounts."
      end

      def check_consent!(user, consent_scope)
        return if ActAsConsent.allows?(user: user, project: project, provider: Github::UserConnection::PROVIDER,
                                       scope: consent_scope)

        raise Refusal, consent_scope == :own ? "#{user.name} has not allowed agents to act as them in their own " \
                                                "tasks in project #{project.name}." :
                                                "#{user.name} has not allowed their GitHub account to be used in " \
                                                "tasks that aren't theirs in project #{project.name}."
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

      def fresh_user_token!(user, credential)
        Oauth::TokenService.fresh(credential, skew: Oauth::TokenService::PRE_START_SKEW)
          .presence || raise(Oauth::ReauthRequired.new(credential))
      rescue Oauth::ReauthRequired, Encryptable::DecryptionError
        raise Refusal, reconnect_message(user)
      end

      def mint_token!(user, credential, user_token, owner, repositories, identity)
        names = repositories.map { |repo| repo.full_name.split("/", 2).last }
        minted = Github::UserTokenService.new.scoped_token(user_token: user_token, target: owner,
                                                           repositories: names, permissions: PERMISSIONS)
        UserTokenIssuance.create!(
          terminal_session: session, company: project.company, project: project, acting_for_user: user,
          session_user: session_user, tool_name: self.class.tool_definition.name,
          provider: Github::UserConnection::PROVIDER, oauth_credential: credential, token: minted[:token],
          token_last_eight: minted[:token_last_eight], target_login: owner,
          repository_full_names: repositories.map(&:full_name), expires_at: minted[:expires_at]
        )
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

      def reconnect_message(user)
        "#{user.name}'s GitHub connection needs to be renewed under Profile → Connected accounts."
      end

      def unarmed_message
        "No token was returned: this session's log redaction could not be armed, and handing out a token the " \
          "container's log filters do not yet know about would write it into the session logs verbatim. Retry — " \
          "if it keeps failing, the container is unreachable from the platform."
      end
    end
  end
end
