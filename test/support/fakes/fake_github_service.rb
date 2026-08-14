# frozen_string_literal: true

# In-memory fakes for the app-owned GitHub adapters (testing doctrine R3:
# "one canonical fake per boundary", docs/testing.md). Caller tests stub the
# real constant and hand back a fake instead of mocking Octokit:
#
#   fake = FakeGithub::TokenService.new(token: "ghs_x")
#   Github::TokenService.stubs(:new).returns(fake)
#   ...
#   assert fake.called?(:generate_installation_token)
#
# The canned return shapes here are the exact shapes the WebMock contract
# tests in test/services/github/{token,repository}_service_test.rb pin the
# real adapters to (R4). If the real parsed shape drifts, those contract tests
# fail — keep the fakes in lockstep with them.
module FakeGithub
  # Mirrors Github::TokenService.
  class TokenService
    DEFAULT_TOKEN = "ghs_fake_installation_token"
    DEFAULT_INSTALLATION = {
      id: 12_345,
      account_login: "acme-corp",
      account_type: "Organization",
      target_type: "Organization",
      permissions: { contents: "read", pull_requests: "write" }
    }.freeze

    # Every call is appended here as { method:, ... } so tests can read what
    # happened. See #called?, #calls_to, #last_call.
    attr_reader :calls

    # @param integration the caller passes it to `.new`; recorded for assertions
    # @param token [String] what #generate_installation_token returns
    # @param installation [Hash] what #verify_installation returns
    # @param token_error [Exception, nil] raised by #generate_installation_token when set
    # @param verify_error [Exception, nil] raised by #verify_installation when set
    #   (use the real Github::TokenService::AuthenticationError to exercise
    #   caller rescue branches)
    # @param unreachable [Array<String>] repo NAMES the installation cannot reach.
    #   Requesting any of them fails the whole call, which is what GitHub does:
    #   a `repositories:` list containing one repository outside the installation
    #   is rejected wholesale with a 422, not trimmed.
    def initialize(integration = nil, token: DEFAULT_TOKEN, installation: DEFAULT_INSTALLATION,
                   token_error: nil, verify_error: nil, unreachable: [])
      @integration = integration
      @token = token
      @installation = installation.dup
      @token_error = token_error
      @verify_error = verify_error
      @unreachable = unreachable.dup
      @calls = []
    end

    def generate_installation_token(repositories: [])
      @calls << { method: :generate_installation_token, repositories: repositories }
      raise @token_error if @token_error

      if (repositories & @unreachable).any?
        raise Github::TokenService::AuthenticationError,
              "Failed to generate installation token: POST https://api.github.com/app/installations/1/access_tokens: " \
              "422 - There is at least one repository that does not exist or is not accessible to the parent installation"
      end

      @token
    end

    def verify_installation
      @calls << { method: :verify_installation }
      raise @verify_error if @verify_error

      @installation.dup
    end

    # ---- call recording readers -------------------------------------------
    def called?(method_name)
      @calls.any? { |call| call[:method] == method_name }
    end

    def calls_to(method_name)
      @calls.select { |call| call[:method] == method_name }
    end

    def last_call
      @calls.last
    end
  end

  # Mirrors Github::CheckStatusService — the read-only CI status adapter the gate
  # reconciler probes with. Hands back real `Ci::ProbeResult`s, so a caller test
  # never has to know what GitHub's own payloads look like; the shapes those
  # results come from are pinned in test/services/github/check_status_service_test.rb.
  class CheckStatusService
    attr_reader :calls

    # @param integration recorded for assertions
    # @param pr_result [Ci::ProbeResult] what #pull_request_checks returns
    # @param run_result [Ci::ProbeResult] what #workflow_run_status returns
    def initialize(integration = nil, pr_result: nil, run_result: nil)
      @integration = integration
      @pr_result = pr_result || Ci::ProbeResult.in_progress("checks still running")
      @run_result = run_result || Ci::ProbeResult.in_progress("workflow run still running")
      @calls = []
    end

    def pull_request_checks(repo_full_name, pr_number)
      @calls << { method: :pull_request_checks, repo_full_name: repo_full_name, pr_number: pr_number }
      @pr_result
    end

    def workflow_run_status(repo_full_name, run_id)
      @calls << { method: :workflow_run_status, repo_full_name: repo_full_name, run_id: run_id }
      @run_result
    end

    # ---- call recording readers -------------------------------------------
    def called?(method_name)
      @calls.any? { |call| call[:method] == method_name }
    end

    def calls_to(method_name)
      @calls.select { |call| call[:method] == method_name }
    end

    def last_call
      @calls.last
    end
  end

  # Mirrors Github::RepositoryService.
  class RepositoryService
    DEFAULT_REPOS = [
      { full_name: "acme/app", default_branch: "main",
        clone_url: "https://github.com/acme/app.git", is_private: false, description: "Main application" },
      { full_name: "acme/infra", default_branch: "develop",
        clone_url: "https://github.com/acme/infra.git", is_private: true, description: nil }
    ].freeze
    DEFAULT_BRANCHES = %w[main develop].freeze

    attr_reader :calls

    # @param integration recorded for assertions
    # @param repos [Array<Hash>] what #list_available returns (and #find_repo looks up in)
    # @param branches [Array<String>] what #list_branches returns
    def initialize(integration = nil, repos: DEFAULT_REPOS, branches: DEFAULT_BRANCHES)
      @integration = integration
      @repos = repos.map(&:dup)
      @branches = branches.dup
      @calls = []
    end

    def list_available
      @calls << { method: :list_available }
      @repos.map(&:dup)
    end

    def find_repo(full_name)
      @calls << { method: :find_repo, full_name: full_name }
      repo = @repos.find { |r| r[:full_name] == full_name }
      repo&.dup
    end

    def list_branches(full_name)
      @calls << { method: :list_branches, full_name: full_name }
      @branches.dup
    end

    # GitHub uses App installation webhooks — configure/remove are no-ops on the
    # real adapter; the fake records them so callers can assert they ran.
    def configure(repository)
      @calls << { method: :configure, repository: repository }
      nil
    end

    def remove(repository)
      @calls << { method: :remove, repository: repository }
      nil
    end

    # ---- call recording readers -------------------------------------------
    def called?(method_name)
      @calls.any? { |call| call[:method] == method_name }
    end

    def calls_to(method_name)
      @calls.select { |call| call[:method] == method_name }
    end

    def last_call
      @calls.last
    end
  end
end
