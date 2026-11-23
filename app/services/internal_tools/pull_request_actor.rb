# frozen_string_literal: true

module InternalTools
  # Makes the person a pull_request_* write acts as (docs/design/bitbucket-integration.md
  # §4.12). It runs the steps of the user-token tools (membership, connected account,
  # consent, a fresh token, the issuance record, each refusal's wording) by including the
  # same contexts, limited to the one repository the call is about. The token goes to the
  # provider and nowhere else: it is not returned to the agent.
  #
  # One subclass per host that has a user identity. A host without one has no subclass,
  # and the parameter is refused there.
  class PullRequestActor
    include Concerns::UserTokenContext

    CLASSES = {
      "github" => "InternalTools::PullRequestActor::GithubActor",
      "gitlab" => "InternalTools::PullRequestActor::GitlabActor",
      "bitbucket" => "InternalTools::PullRequestActor::BitbucketActor"
    }.freeze

    # @return [PullRequests::Acting]
    # @raise [PullRequests::Error] with the token tools' wording when the user may not be acted as
    def self.acting_as(user, session:, repository:, tool_name:)
      provider = repository.integration.provider.to_s
      klass = CLASSES[provider]&.constantize
      unless klass
        raise PullRequests::Error.new("#{provider.titleize} has no user identity yet, so pull requests there cannot be " \
                                      "made as a person. Leave out user_id to act as the connection.",
                                      code: "unsupported")
      end

      klass.new(session: session, repository: repository, tool_name: tool_name).acting_as(user)
    end

    def initialize(session:, repository:, tool_name:)
      @session = session
      @repository = repository
      @tool_name = tool_name
    end

    def acting_as(user)
      scope = user.id == session_user&.id ? :own : :others
      acquired = acquire_user_tokens(user: user, consent_scope: scope)
      token = acquired.tokens.first&.fetch(:token)
      raise Concerns::UserTokenContext::Refusal, no_identity_message if token.blank?

      PullRequests::Acting.new(user_id: user.id, login: login_of(acquired.identity), token: token)
    rescue Concerns::UserTokenContext::Refusal => e
      raise PullRequests::Error.new(e.message, code: "permission_denied")
    end

    private

    attr_reader :session

    def project = session&.project
    def session_user = session&.user
    def issuing_tool_name = @tool_name

    # The user-token contexts cover the session's repositories; a write is about one.
    def only_target((covered, skipped))
      [ covered.select { |repo| repo.id == @repository.id },
        skipped.select { |entry| entry[:repository] == @repository.full_name } ]
    end

    class GithubActor < PullRequestActor
      include Concerns::GithubUserTokenContext

      private

      def collect_repositories = only_target(super)
      def login_of(identity) = identity["login"]
    end

    class GitlabActor < PullRequestActor
      include Concerns::GitlabUserTokenContext

      private

      def collect_repositories = only_target(super)
      def login_of(identity) = identity["username"]
    end

    class BitbucketActor < PullRequestActor
      include Concerns::BitbucketUserTokenContext

      private

      def collect_repositories = only_target(super)
      def login_of(identity) = identity["nickname"]
    end
  end
end
