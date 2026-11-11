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
      @session     = create(:terminal_session, :running, project: @project, user: @user)
      @session.repositories << @repository
      @runner      = FakeRunner.new
    end

    def prepare(path: nil, repository: nil, ref: nil, session: @session)
      Github::TokenService.stub(:new, ->(integration) { FakeTokenService.new(integration) }) do
        Coder::RepoBootstrap.new(@coder, ssh_runner: @runner).prepare(
          workspace_name: "ws-1",
          repository:     repository || @repository,
          session:        session,
          path:           path,
          ref:            ref
        )
      end
    end

    # A session in the project an Azure or Bitbucket connection is scoped to,
    # holding that connection's repository.
    def session_holding(repository)
      session = create(:terminal_session, :running, project: repository.scope, user: repository.scope.owner)
      session.repositories << repository
      session
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

      assert_equal "x-access-token", @runner.env["AIXLE_GIT_USERNAME"]
      assert_equal "ghs_faketoken_app", @runner.env["AIXLE_GIT_PASSWORD"]
      assert_no_match(/ghs_faketoken/, @runner.command)
      assert_match(/git -c credential\.helper="\$HELPER" clone/, @runner.command)
      assert_match(/password=\$AIXLE_GIT_PASSWORD/, @runner.command)
    end

    test "a public repository is cloned with no credential at all" do
      public_repo = create(:repository, :public_source, full_name: "torvalds/linux",
                                        clone_url: "https://github.com/torvalds/linux.git", scope: @project)

      result = Coder::RepoBootstrap.new(@coder, ssh_runner: @runner).prepare(
        workspace_name: "ws-1", repository: public_repo, session: @session
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

    test "refuses a repository the session does not hold" do
      other = create(:repository, full_name: "acme/other", integration: @github, scope: @project)

      error = assert_raises(Coder::RepoBootstrap::Error) { prepare(repository: other) }
      assert_match(/no credential for acme\/other: repository is not attached to this session/, error.message)
      assert_nil @runner.command
    end

    # ---------- other providers ----------

    test "clones a GitLab repository with its token as the oauth2 user" do
      gitlab = create(:integration, :gitlab, :active, company: @company, connected_by: @user)
      repo   = create(:repository, full_name: "acme/gl", integration: gitlab, scope: @project,
                                   clone_url: "https://gitlab.com/acme/gl.git")
      @session.repositories << repo

      prepare(repository: repo)

      token = gitlab.credentials_data["personal_access_token"]
      assert_equal({ "AIXLE_GIT_USERNAME" => "oauth2", "AIXLE_GIT_PASSWORD" => token }, @runner.env)
      assert_match(%r{^URL='https://gitlab\.com/acme/gl\.git'$}, @runner.command)
      assert_match(/git -c credential\.helper="\$HELPER" clone/, @runner.command)
      assert_no_match(/#{Regexp.escape(token)}/, @runner.command)
    end

    # Bitbucket refuses an access token under any user but x-token-auth.
    test "clones a Bitbucket repository under the username its token kind needs" do
      repo    = create(:repository, :bitbucket, full_name: "acme/service", source_branch: "main")
      session = session_holding(repo)

      prepare(repository: repo, session: session)

      token = repo.integration.credentials_data["token"]
      assert_equal({ "AIXLE_GIT_USERNAME" => "x-token-auth", "AIXLE_GIT_PASSWORD" => token }, @runner.env)
      assert_match(%r{^URL='https://bitbucket\.org/acme/service\.git'$}, @runner.command)
      assert_no_match(/#{Regexp.escape(token)}/, @runner.command)
    end

    # An Entra token is only accepted as a bearer header; the helper protocol
    # cannot carry one on the gits these boxes run.
    test "clones an Azure DevOps repository with a bearer header taken from the environment" do
      with_azure_devops_enabled
      integration = create(:integration, :azure_devops, :active, company: @company)
      repo        = create(:repository, :azure_devops, integration: integration)
      session     = session_holding(repo)
      stub_azure_token(tenant_id: integration.azure_devops_installation.tenant_id, token: "entra-clone-token")

      result = prepare(repository: repo, session: session)

      assert_equal "/root/#{repo.repo_name}", result[:path]
      assert_equal({ "AIXLE_GIT_AUTH_HEADER" => "Authorization: Bearer entra-clone-token" }, @runner.env)
      assert_match(/git --config-env=http\.extraheader=AIXLE_GIT_AUTH_HEADER clone/, @runner.command)
      assert_match(/git --config-env=http\.extraheader=AIXLE_GIT_AUTH_HEADER -C "\$TARGET" fetch/, @runner.command)
      assert_no_match(/credential\.helper="\$HELPER"/, @runner.command)
      assert_no_match(/entra-clone-token/, @runner.command)
    end

    test "clones an Azure DevOps repository connected with a PAT through a basic header" do
      with_azure_devops_enabled(pat_mode: true)
      integration = create(:integration, :azure_devops_pat, :active, company: @company)
      repo        = create(:repository, :azure_devops, integration: integration)
      session     = session_holding(repo)

      prepare(repository: repo, session: session, ref: "main")

      pat = integration.credentials_data["personal_access_token"]
      assert_equal "Authorization: Basic #{Base64.strict_encode64(":#{pat}")}", @runner.env["AIXLE_GIT_AUTH_HEADER"]
      assert_match(/--config-env=http\.extraheader=AIXLE_GIT_AUTH_HEADER -C "\$TARGET" fetch --force origin/,
                   @runner.command)
      assert_no_match(/#{Regexp.escape(pat)}/, @runner.command)
    end

    test "says why when Azure DevOps will not vend a credential" do
      with_azure_devops_enabled
      integration = create(:integration, :azure_devops, :active, company: @company)
      repo        = create(:repository, :azure_devops, integration: integration)
      stranger    = create(:terminal_session, :running, project: @project, user: @user)

      error = assert_raises(Coder::RepoBootstrap::Error) { prepare(repository: repo, session: stranger) }
      assert_match(/no Azure DevOps credential for .+: Repository \d+ is not attached to this session/, error.message)
      assert_nil @runner.command
    end
  end
end
