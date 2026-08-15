# frozen_string_literal: true

module Fakes
  # In-memory stand-in for the app-owned GitLab adapters
  # (`Gitlab::RepositoryService` + `Gitlab::TokenService`). One fake covers both
  # thin adapters because callers reach GitLab through the same credential.
  #
  # Use this in caller tests instead of stubbing the gitlab gem (testing doctrine
  # R2/R3): stub `Gitlab::RepositoryService.new` / `Gitlab::TokenService.new`
  # (or `RepositoryService.for`) to return an instance of this class.
  #
  # The canned return shapes below are the SAME parsed shapes the real adapters
  # produce; those shapes are pinned against the live GitLab API by the WebMock
  # contract tests in test/services/gitlab/{token,repository}_service_test.rb —
  # so this fake cannot silently drift from reality (R4).
  #
  # Every public method records its call in #calls so callers can assert
  # behaviour (which repo was configured, whether verify_token ran, ...).
  class FakeGitlabService
    Call = Struct.new(:name, :args, keyword_init: true)

    DEFAULT_USER = {
      id: 152, username: "alice", name: "Alice Smith", email: "alice@example.com"
    }.freeze

    DEFAULT_REPOS = [
      { full_name: "group/app", default_branch: "main",
        clone_url: "https://gitlab.com/group/app.git", is_private: true, description: "Main app" },
      { full_name: "group/lib", default_branch: "develop",
        clone_url: "https://gitlab.com/group/lib.git", is_private: false, description: nil }
    ].freeze

    DEFAULT_BRANCHES = %w[main develop].freeze

    attr_reader :calls

    # user:         Hash returned by #verify_token — {id:, username:, name:, email:}
    # repos:        Array<Hash> returned by #list_available / looked up by #find_repo
    # branches:     Hash full_name => [names]; falls back to DEFAULT_BRANCHES
    # verify_error: Exception (class or instance) #verify_token should raise
    #               instead of returning — e.g. Gitlab::TokenService::AuthenticationError
    # pipeline_result: Ci::ProbeResult returned by #pipeline_status (the
    #               Gitlab::PipelineStatusService interface, used by the CI gate
    #               reconciler). Defaults to "still running".
    def initialize(user: DEFAULT_USER, repos: DEFAULT_REPOS, branches: {}, verify_error: nil,
                   pipeline_result: nil)
      @user = user
      @repos = repos.map(&:dup)
      @branches = branches
      @verify_error = verify_error
      @pipeline_result = pipeline_result
      @calls = []
    end

    # --- Gitlab::TokenService interface -------------------------------------

    def verify_token
      record(:verify_token)
      raise @verify_error if @verify_error

      @user
    end

    # --- Gitlab::RepositoryService interface --------------------------------

    def list_available
      record(:list_available)
      @repos
    end

    def find_repo(full_name)
      record(:find_repo, full_name)
      @repos.find { |repo| repo[:full_name] == full_name }
    end

    def list_branches(full_name)
      record(:list_branches, full_name)
      @branches.fetch(full_name, DEFAULT_BRANCHES)
    end

    # Mirrors the real adapter's observable effect: stamp a webhook_secret on the
    # repository and return it. Skips the network the real adapter would hit.
    def configure(repository)
      record(:configure, repository)
      secret = SecureRandom.hex(32)
      repository.update!(webhook_secret: secret)
      secret
    end

    def remove(repository)
      record(:remove, repository)
      nil
    end

    # --- Gitlab::PipelineStatusService interface -----------------------------

    def pipeline_status(full_name, pipeline_id)
      record(:pipeline_status, full_name, pipeline_id)
      @pipeline_result || Ci::ProbeResult.in_progress("pipeline #{pipeline_id} is running")
    end

    # --- Call introspection for assertions ----------------------------------

    def called?(name)
      @calls.any? { |call| call.name == name }
    end

    def calls_for(name)
      @calls.select { |call| call.name == name }
    end

    private

    def record(name, *args)
      @calls << Call.new(name: name, args: args)
    end
  end
end
