# frozen_string_literal: true

module PullRequests
  # The port every code host with pull-request tools implements
  # (docs/design/bitbucket-integration.md §4.3). One instance per connection.
  #
  # Every method takes the Aixle Repository it acts in and must refuse a pull
  # request that is not that repository's: a number alone does not say which
  # repository it belongs to. `ref` is what the caller has, a number or a
  # browser URL. Values come back as PullRequests::PullRequest, Comment, …,
  # errors as PullRequests::Error.
  class Provider
    def self.for(integration)
      klass = PullRequests.provider_class(integration.provider)
      raise Error::Unsupported, "#{integration.provider} has no pull-request tools" unless klass

      klass.new(integration)
    end

    attr_reader :integration

    def initialize(integration)
      @integration = integration
    end

    def list(_repository, state:, source_branch:, cursor:, limit:) = raise NotImplementedError
    def get(_repository, _ref) = raise NotImplementedError
    def changes(_repository, _ref, cursor:, limit:) = raise NotImplementedError

    def create(_repository, source_branch:, target_branch:, title:, description:, draft:)
      raise NotImplementedError
    end

    # Only the given attributes change; `state` is "open" or "closed".
    def update(_repository, _ref, **_attributes) = raise NotImplementedError

    def list_comments(_repository, _ref, cursor:, limit:) = raise NotImplementedError
    def add_comment(_repository, _ref, body:, file_path:, line:, reply_to:) = raise NotImplementedError
    def review(_repository, _ref, verdict:, body:) = raise NotImplementedError

    def merge(_repository, _ref, expected_head_sha:, strategy:, delete_source_branch:, message:)
      raise NotImplementedError
    end

    def checks(_repository, _ref) = raise NotImplementedError

    # True when `ref` is a browser URL of a pull request in `repository`.
    def owns_reference?(_repository, _ref) = false

    # The number in `ref`: an integer, a numeric string, or the trailing number
    # of a pull-request URL this provider owns for `repository`.
    def number_of(repository, ref)
      text = ref.to_s.strip
      return text.to_i if text.match?(/\A\d+\z/)
      return text[%r{/(\d+)(?:/[^/]*)?/?\z}, 1].to_i if owns_reference?(repository, text)

      raise Error.new("#{ref.inspect} is not a pull request of #{repository.full_name}", code: "validation_failed")
    end
  end
end
