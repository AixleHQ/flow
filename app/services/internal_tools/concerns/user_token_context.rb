# frozen_string_literal: true

module InternalTools
  module Concerns
    # The steps every user-token tool shares (docs/design/github-user-identity.md §4.3,
    # docs/design/gitlab-user-identity.md §4.2), in order; the first failure answers
    # with an error. A tool names the user it acts for and the consent switch that user
    # must have turned on.
    #
    # The including module supplies the provider's part:
    #   provider_label                          "GitHub"
    #   provider_name                           the provider string ("github")
    #   live_connection_of(user)                the user's OauthCredential, or nil
    #   identity_of(credential)                 the stored identity (a Hash) or nil
    #   identity_usable?(identity)              whether it can be committed with
    #   collect_repositories                    [repositories to cover, skipped entries]
    #   no_repositories_message                 the refusal when there are none
    #   token_skew                              how much life the user's token must have left
    #   mint_tokens!(user, credential, user_token, repositories, identity)
    #                                           [tokens, further skipped entries]
    #   result(user, identity, tokens, skipped) the JSON-able answer
    #
    # Messages never carry a token or a provider response body: InternalToolExecutor
    # hands exception messages to the agent.
    module UserTokenContext
      extend ActiveSupport::Concern

      NO_USER = "This session has no user, so there is no one to act as."
      NO_PROJECT = "This session has no project."

      class Refusal < StandardError; end

      private

      def issue_user_tokens(user:, consent_scope:)
        raise Refusal, NO_USER if session_user.nil?
        raise Refusal, NO_PROJECT if project.nil?

        check_member!(user)
        credential = connection_for!(user)
        check_consent!(user, consent_scope)
        repositories, skipped = collect_repositories
        raise Refusal, no_repositories_message if repositories.empty?

        user_token = fresh_user_token!(user, credential)
        identity = identity_of(credential)
        raise Refusal, no_identity_message unless identity_usable?(identity)

        tokens, more_skipped = mint_tokens!(user, credential, user_token, repositories, identity)
        raise Refusal, unarmed_message unless Sessions::SecretRegistry.publish!(session)

        success(result(user, identity, tokens, skipped + more_skipped).to_json)
      rescue Refusal => e
        error(e.message)
      end

      def check_member!(user)
        return if user.authenticatable? && project.accessible_by?(user)

        raise Refusal, "#{user.name} is not a member of project #{project.name}."
      end

      def connection_for!(user)
        credential = live_connection_of(user)
        return credential if credential

        raise Refusal, "#{user.name} has not connected a #{provider_label} account. " \
                       "They can connect one under Profile → Connected accounts."
      end

      def check_consent!(user, consent_scope)
        return if ActAsConsent.allows?(user: user, project: project, provider: provider_name, scope: consent_scope)

        raise Refusal, consent_scope == :own ? "#{user.name} has not allowed agents to act as them in their own " \
                                                "tasks in project #{project.name}." :
                                                "#{user.name} has not allowed their #{provider_label} account to be " \
                                                "used in tasks that aren't theirs in project #{project.name}."
      end

      def fresh_user_token!(user, credential)
        Oauth::TokenService.fresh(credential, skew: token_skew)
          .presence || raise(Oauth::ReauthRequired.new(credential))
      rescue Oauth::ReauthRequired, Encryptable::DecryptionError
        raise Refusal, reconnect_message(user)
      end

      def record_issuance!(user:, credential:, token:, target_login:, repositories:, expires_at:, token_last_eight: nil)
        UserTokenIssuance.create!(
          terminal_session: session, company: project.company, project: project, acting_for_user: user,
          session_user: session_user, tool_name: self.class.tool_definition.name, provider: provider_name,
          oauth_credential: credential, token: token, token_last_eight: token_last_eight || token.to_s.last(8),
          target_login: target_login, repository_full_names: repositories.map(&:full_name), expires_at: expires_at
        )
      end

      def no_identity_message
        "#{provider_label} did not return this account's identity. Retry in a moment, or reconnect the account " \
          "under Profile → Connected accounts."
      end

      def reconnect_message(user)
        "#{user.name}'s #{provider_label} connection needs to be renewed under Profile → Connected accounts."
      end

      def unarmed_message
        "No token was returned: this session's log redaction could not be armed, and handing out a token the " \
          "container's log filters do not yet know about would write it into the session logs verbatim. Retry — " \
          "if it keeps failing, the container is unreachable from the platform."
      end
    end
  end
end
