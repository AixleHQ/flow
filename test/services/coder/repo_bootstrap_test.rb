# frozen_string_literal: true

require "test_helper"

module Coder
  class RepoBootstrapTest < ActiveSupport::TestCase
    # Captures what would be sent to the workspace. Stands in for the app-owned
    # Coder::SshRunner through its constructor seam.
    class FakeRunner
      attr_reader :command, :env, :job_id

      def exec_detached(workspace_name:, command:, job_id: nil, env: {})
        @command = command
        @env     = env
        @job_id  = job_id
        { job_id: "j1", job_dir: "/var/lib/aixle-jobs", log_path: "/var/lib/aixle-jobs/j1.log", detached: true }
      end
    end

    class FakeTokenService
      def initialize(_integration) = nil
      def generate_installation_token(repositories: []) = "ghs_faketoken_#{repositories.join}"
    end

    setup do
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @project     = create(:project, company: @company, owner: @user)
      @coder       = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @github      = create(:integration, :github, :active, company: @company, connected_by: @user)
      @repository  = create(:repository, full_name: "acme/app", source_branch: "develop",
                                         integration: @github, scope: @project)
      @runner      = FakeRunner.new
    end

    def prepare(path: nil, repository: nil)
      Github::TokenService.stub(:new, ->(integration) { FakeTokenService.new(integration) }) do
        Coder::RepoBootstrap.new(@coder, ssh_runner: @runner).prepare(
          workspace_name: "ws-1",
          repository:     repository || @repository,
          path:           path
        )
      end
    end

    test "clones into /root/<repo name> by default and reports the job handle" do
      result = prepare

      assert_equal "j1", result[:job_id]
      assert_equal "/root/app", result[:path]
      assert_equal "acme/app", result[:repository]
      assert_equal "develop", result[:branch]
      assert_match(/clone --branch "\$BRANCH"/, @runner.command)
    end

    test "adopts an existing clone at the path a previous session left behind" do
      result = prepare(path: "/root/app")

      assert_equal "/root/app", result[:path]
      assert_match(%r{TARGET='/root/app'}, @runner.command)
    end

    # The three things every session was rediscovering by hand.
    test "repairs the refspec, the partial-clone filter and the shallow history" do
      prepare

      assert_match(/config remote\.origin\.fetch '\+refs\/heads\/\*:refs\/remotes\/origin\/\*'/, @runner.command)
      assert_match(/--unset-all remote\.origin\.promisor/, @runner.command)
      assert_match(/--unset-all remote\.origin\.partialclonefilter/, @runner.command)
      assert_match(/fetch --unshallow/, @runner.command)
    end

    test "never lets an unauthenticated fetch hang on a credential prompt" do
      prepare

      assert_match(/GIT_TERMINAL_PROMPT=0/, @runner.command)
      assert_match(%r{GIT_ASKPASS=/bin/true}, @runner.command)
    end

    # The workspace is shared and long-lived: a credential written into
    # remote.origin.url or into the job's command file outlives the session.
    test "passes the token through the environment and never into the command" do
      prepare

      assert_equal "ghs_faketoken_app", @runner.env["AIXLE_GH_TOKEN"]
      assert_no_match(/ghs_faketoken/, @runner.command)
      assert_match(/credential\.helper/, @runner.command)
      assert_match(/\$AIXLE_GH_TOKEN/, @runner.command)
    end

    test "a public repository is cloned with no credential at all" do
      public_repo = create(:repository, :public_source, full_name: "torvalds/linux",
                                        clone_url: "https://github.com/torvalds/linux.git", scope: @project)

      result = Coder::RepoBootstrap.new(@coder, ssh_runner: @runner).prepare(
        workspace_name: "ws-1", repository: public_repo
      )

      assert_equal "/root/linux", result[:path]
      assert_empty @runner.env
      assert_no_match(/credential\.helper="\$HELPER"/, @runner.command)
    end

    test "refuses a relative path" do
      error = assert_raises(Coder::RepoBootstrap::Error) { prepare(path: "app") }
      assert_match(/must be absolute/, error.message)
    end

    test "refuses a repository whose integration is not active" do
      @github.update!(status: :error)

      error = assert_raises(Coder::RepoBootstrap::Error) { prepare }
      assert_match(/no active integration/, error.message)
    end

    test "says plainly that GitLab is not supported yet" do
      gitlab = create(:integration, :gitlab, :active, company: @company, connected_by: @user)
      repo   = create(:repository, full_name: "acme/gl", integration: gitlab, scope: @project,
                                   clone_url: "https://gitlab.com/acme/gl.git")

      error = assert_raises(Coder::RepoBootstrap::Error) { prepare(repository: repo) }
      assert_match(/gitlab repositories are not supported yet/i, error.message)
    end
  end
end
