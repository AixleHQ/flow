# frozen_string_literal: true

module Tools
  module PersonalMCP
    # What a personal-MCP request authenticated with: the user's static token or
    # an OAuth grant an app holds. Each was issued under the sign-in proofs of
    # one browser session, which decide the companies it reaches.
    class Credential
      attr_reader :user, :noun, :reissue_hint

      def self.token(user)
        new(user, user.mcp_token_proven_provider_ids, noun: "token",
                                                      reissue_hint: "regenerate the token from your profile")
      end

      def self.grant(grant)
        new(grant.user, grant.proof_provider_ids, noun: "connection",
                                                  reissue_hint: "connect #{grant.client_name} to Aixle again")
      end

      def initialize(user, provider_ids, noun:, reissue_hint:)
        @user = user
        @provider_ids = provider_ids
        @noun = noun
        @reissue_hint = reissue_hint
      end

      def company_ids
        Auth::PolicyResolver.satisfied_company_ids(
          company_ids: user.company_memberships.active.select(:company_id),
          provider_ids: @provider_ids
        )
      end
    end
  end
end
