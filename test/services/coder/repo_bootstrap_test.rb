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

    def prepare(path: nil, repository: nil, ref: nil)
      Github::TokenService.stub(:new, ->(integration) { FakeTokenService.new(integration) }) do
        Coder::RepoBootstrap.new(@coder, ssh_runner: @runner).prepare(
          workspace_name: "ws-1",
          repository:     repository || @repository,
          path:           path,
          ref:            ref
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

    # ---------- ref ----------

    test "reports the revision it left the clone on so the caller can verify it" do
      prepare

      assert_match(/#{Regexp.escape(Coder::SshRunner::JOB_RESULT_MARKER)}/, @runner.command)
      assert_match(/echo "head_sha=\$\(git -C "\$TARGET" rev-parse HEAD\)"/, @runner.command)
      assert_match(/echo "worktree=\$WORKTREE"/, @runner.command)
      assert_match(/status --porcelain/, @runner.command)
    end

    test "without a ref nothing is checked out and the handle stays as it was" do
      result = prepare

      assert_not result.key?(:ref)
      assert_match(/^REF=''$/, @runner.command)
      assert_no_match(/checkout/, @runner.command)
    end

    test "a blank ref is treated as no ref at all" do
      result = prepare(ref: "   ")

      assert_not result.key?(:ref)
      assert_no_match(/checkout/, @runner.command)
    end

    # Branch, then tag, then commit — one ref must always land on one revision.
    test "checks out a requested ref, resolving branch then tag then commit" do
      result = prepare(ref: "feature/login")

      assert_equal "feature/login", result[:ref]
      assert_match(/^REF='feature\/login'$/, @runner.command)
      assert_match(%r{fetch --force origin "\+refs/heads/\$REF:refs/remotes/origin/\$REF"}, @runner.command)
      assert_match(/checkout --force -B "\$REF" "refs\/remotes\/origin\/\$REF"/, @runner.command)
      assert_match(%r{fetch --force origin "\+refs/tags/\$REF:refs/tags/\$REF"}, @runner.command)
      assert_match(/checkout --force --detach "refs\/tags\/\$REF"/, @runner.command)
      assert_match(/rev-parse --verify --quiet "\$REF\^\{commit\}"/, @runner.command)
      assert_match(/checkout --force --detach "\$REF"/, @runner.command)
    end

    test "a ref that exists nowhere on origin fails the job with its own exit code" do
      prepare(ref: "0f1e2d3c4b5a69788796a5b4c3d2e1f001234567")

      assert_match(/is not a branch, tag or commit on origin/, @runner.command)
      assert_match(/exit #{Coder::RepoBootstrap::REF_NOT_FOUND_EXIT_CODE}$/, @runner.command)
    end

    test "the ref fetch is authenticated like every other fetch" do
      prepare(ref: "develop")

      ref_block = @runner.command[/checking out \$REF.*\z/m] || @runner.command[/if \[ -n "\$REF" \].*\z/m]
      assert_not_nil ref_block
      assert_equal 0, ref_block.scan(/git -C "\$TARGET" fetch/).size,
        "every fetch in the ref block must carry the credential helper"
      assert_match(/credential\.helper="\$HELPER" -C "\$TARGET" fetch/, ref_block)
    end

    test "refuses a ref that is not a plain branch, tag or commit name" do
      [
        "main; rm -rf /",
        "--upload-pack=evil",
        "feature branch",
        "a..b",
        "refs//heads/x",
        "topic/",
        "topic.lock",
        "$(whoami)"
      ].each do |bad_ref|
        error = assert_raises(Coder::RepoBootstrap::Error, "expected #{bad_ref.inspect} to be refused") do
          prepare(ref: bad_ref)
        end
        assert_match(/is not a valid branch, tag or commit name/, error.message)
      end
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
