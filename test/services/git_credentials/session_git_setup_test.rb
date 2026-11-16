# frozen_string_literal: true

require "test_helper"

module GitCredentials
  # A write the runtime could not complete answers false rather than raising, so
  # it has to be checked where it happens: a missing credential file otherwise
  # surfaces as git's own confusing clone error, and a missing helper as every
  # later fetch and push failing.
  class SessionGitSetupTest < ActiveSupport::TestCase
    setup do
      company = create(:company)
      user = create(:user, :admin, company: company)
      project = create(:project, company: company, owner: user)
      integration = create(:integration, company: company, connected_by: user, status: :active)
      @repository = create(:repository, full_name: "acme/my-app", source_branch: "main",
                                        integration: integration, scope: project)
      session = create(:terminal_session, user: user, project: project, agent_type: "claude_code")
      session.repositories << @repository
      Github::TokenService.stubs(:new).returns(FakeGithub::TokenService.new(token: "ghs_test_token"))

      @runtime = ContainerRuntime::FakeRuntime.new
      @setup = SessionGitSetup.new(runtime: @runtime, container_id: "c1", session: session)
    end

    test "a clone credential that could not be written fails the clone before git runs" do
      @runtime.fail_write(%r{\A/tmp/\.aixle-git-})

      _stdout, stderr, exit_code = @setup.clone(@repository, "/workspace/repo/my-app", 1001)

      assert_equal 1, exit_code
      assert_match(/could not write the clone credential/, Array(stderr).join)
      assert_not git_clone_ran?
    end

    test "a helper that could not be written fails the clone instead of leaving fetch and push to fail later" do
      @runtime.fail_write(SessionGitSetup::HELPER)

      _stdout, stderr, exit_code = @setup.clone(@repository, "/workspace/repo/my-app", 1001)

      assert_equal 1, exit_code
      assert_match(/could not write the git credential helper/, Array(stderr).join)
      assert_not git_clone_ran?
    end

    test "a clone writes only under /workspace and /tmp, since a Kubernetes exec runs as the non-root agent user" do
      _stdout, _stderr, exit_code = @setup.clone(@repository, "/workspace/repo/my-app", 1001)

      written = @runtime.fs.keys.select { |path| @runtime.file_attributes(path) }
      assert_equal 0, exit_code
      assert_not_empty written
      assert_empty written.reject { |path| path.start_with?("/workspace/", "/tmp/") }
    end

    test "installing the helper on its own says so when it cannot be written" do
      @runtime.fail_write(SessionGitSetup::HELPER)

      assert_raises(SessionGitSetup::HelperNotInstalled) { @setup.install_helper!(1001) }
    end

    test "a clone marks the checkout as safe in the system git config, once" do
      @setup.clone(@repository, "/workspace/repo/my-app", 1001)

      script = clone_script
      assert_includes script, "git config --system --add safe.directory /workspace/repo/my-app"
      assert_includes script, "grep -qxF -- /workspace/repo/my-app"
      assert_operator script.index("chown -R"), :<, script.index("safe.directory")
    end

    test "reconfiguring an existing checkout adds the entry too" do
      script = @setup.reconfigure_script(@repository, "/workspace/repo/my-app", 1001)

      assert_includes script, "git config --system --add safe.directory /workspace/repo/my-app"
      assert_includes script, "grep -qxF -- /workspace/repo/my-app"
    end

    test "the entry is added to a real system config once, and a failed write does not fail the script" do
      Dir.mktmpdir do |dir|
        env = { "GIT_CONFIG_SYSTEM" => File.join(dir, "gitconfig"), "GIT_CONFIG_NOSYSTEM" => nil }
        script = GitCredentials::SafeDirectory.script("/workspace/repo/my app", scope: :system)

        2.times { assert system(env, "sh", "-c", script) }
        out = IO.popen(env, [ "git", "config", "--system", "--get-all", "safe.directory" ], &:read)
        assert_equal "/workspace/repo/my app\n", out

        unwritable = { "GIT_CONFIG_SYSTEM" => File.join(dir, "missing", "gitconfig") }
        assert system(unwritable, "sh", "-c", script, err: File::NULL)
      end
    end

    test "the global scope is added to a real global config once, and a failed write does not fail the script" do
      Dir.mktmpdir do |dir|
        env = { "HOME" => dir, "GIT_CONFIG_GLOBAL" => File.join(dir, ".gitconfig") }
        script = GitCredentials::SafeDirectory.script("/root/my app", scope: :global)

        2.times { assert system(env, "sh", "-c", script) }
        out = IO.popen(env, [ "git", "config", "--global", "--get-all", "safe.directory" ], &:read)
        assert_equal "/root/my app\n", out

        unwritable = { "HOME" => dir, "GIT_CONFIG_GLOBAL" => File.join(dir, "missing", ".gitconfig") }
        assert system(unwritable, "sh", "-c", script, err: File::NULL)
      end
    end

    test "an unknown or missing scope is refused" do
      assert_raises(ArgumentError) { GitCredentials::SafeDirectory.script("/p", scope: :local) }
      assert_raises(ArgumentError) { GitCredentials::SafeDirectory.script("/p", scope: "system") }
      assert_raises(ArgumentError) { GitCredentials::SafeDirectory.script("/p") }
    end

    test "chained after a failing command the fragment keeps that exit code" do
      script = "false && #{GitCredentials::SafeDirectory.script('/p', scope: :system)}"

      assert_not system("sh", "-c", script)
      assert_equal 1, $?.exitstatus
    end

    # The kept-checkout cases run the real script against real git repositories on
    # disk: the remote is a local bare repository, so the fetch is a real fetch.
    test "no checkout yet: the path is cloned" do
      with_remote do |dir, remote|
        target = File.join(dir, "repo", "app")

        assert run_sync(remote, target)

        assert_equal sha(remote, "main"), sha(target, "HEAD")
        assert_equal "true", git(target, "config", "credential.useHttpPath")
      end
    end

    test "a kept checkout is fetched, not cloned again, and sees a commit pushed in between" do
      with_remote do |dir, remote|
        target = File.join(dir, "app")
        assert run_sync(remote, target)
        git(target, "config", "--local", "marker.kept", "yes")
        push_commit(dir, remote, "second")

        assert run_sync(remote, target)

        assert_equal "yes", git(target, "config", "marker.kept"), "the checkout was kept, not replaced"
        assert_equal sha(remote, "main"), sha(target, "HEAD")
      end
    end

    test "a kept checkout with local changes, untracked files and another branch is put back on the source branch" do
      with_remote do |dir, remote|
        target = File.join(dir, "app")
        assert run_sync(remote, target)
        git(target, "checkout", "-q", "-b", "side")
        File.write(File.join(target, "README"), "edited")
        File.write(File.join(target, "junk"), "x")
        git(target, "-c", "user.name=a", "-c", "user.email=a@b", "commit", "-qam", "local")
        File.write(File.join(target, "README"), "dirty again")
        push_commit(dir, remote, "second")

        assert run_sync(remote, target)

        assert_equal "main", git(target, "rev-parse", "--abbrev-ref", "HEAD")
        assert_equal sha(remote, "main"), sha(target, "HEAD")
        assert_equal "", git(target, "status", "--porcelain")
      end
    end

    test "a kept checkout leaves no credential in its config, even one an earlier session left" do
      with_remote do |dir, remote|
        target = File.join(dir, "app")
        assert run_sync(remote, target)
        git(target, "remote", "set-url", "origin", "file://old-token@#{remote}")
        git(target, "config", "http.extraheader", "Authorization: Basic OLD")

        assert run_sync(remote, target, header: "Authorization: Basic NEW")

        config = File.read(File.join(target, ".git", "config"))
        assert_no_match(/OLD|NEW|old-token|extraheader/, config)
      end
    end

    test "a stale index lock from a killed session does not stop the update" do
      with_remote do |dir, remote|
        target = File.join(dir, "app")
        assert run_sync(remote, target)
        File.write(File.join(target, ".git", "index.lock"), "")

        assert run_sync(remote, target)
        assert_equal sha(remote, "main"), sha(target, "HEAD")
      end
    end

    test "a path holding another remote is replaced by a clone of this one" do
      with_remote do |dir, remote|
        other = File.join(dir, "other.git")
        system("git", "clone", "-q", "--bare", remote, other, exception: true)
        target = File.join(dir, "app")
        system("git", "clone", "-q", other, target, exception: true)

        assert run_sync(remote, target)

        assert_equal "file://#{remote}", git(target, "config", "remote.origin.url")
      end
    end

    test "a broken or partial clone, a plain directory and a file are replaced" do
      with_remote do |dir, remote|
        broken = File.join(dir, "broken")
        FileUtils.mkdir_p(File.join(broken, ".git"))
        plain = File.join(dir, "plain")
        FileUtils.mkdir_p(plain)
        File.write(File.join(plain, "stray"), "x")
        file = File.join(dir, "file")
        File.write(file, "x")
        corrupt = File.join(dir, "corrupt")
        assert run_sync(remote, corrupt)
        FileUtils.rm_rf(Dir[File.join(corrupt, ".git", "objects", "??")])
        File.write(File.join(corrupt, ".git", "HEAD"), "garbage")

        [ broken, plain, file, corrupt ].each do |target|
          assert run_sync(remote, target), target
          assert_equal sha(remote, "main"), sha(target, "HEAD"), target
          assert_not File.exist?(File.join(target, "stray"))
        end
      end
    end

    test "a source branch the remote no longer has fails and does not report success" do
      with_remote do |dir, remote|
        target = File.join(dir, "app")
        assert run_sync(remote, target)

        assert_not run_sync(remote, target, branch: "gone")
      end
    end

    test "a relative or root checkout path is refused" do
      assert_raises(ArgumentError) { @setup.sync_script(@repository, "app", "u") }
      assert_raises(ArgumentError) { @setup.sync_script(@repository, "/", "u") }
    end

    test "the clone script updates a kept checkout through sync_script" do
      @setup.clone(@repository, "/workspace/repo/my-app", 1001)

      assert_includes clone_script, "update_clone"
      assert_includes clone_script, "fetch --prune origin"
    end

    private

    def with_remote
      Dir.mktmpdir do |dir|
        work = File.join(dir, "work")
        remote = File.join(dir, "remote.git")
        system("git", "init", "-q", "-b", "main", work, exception: true)
        File.write(File.join(work, "README"), "one")
        system("git", "-C", work, "add", ".", exception: true)
        system("git", "-C", work, "-c", "user.name=a", "-c", "user.email=a@b", "commit", "-qm", "one", exception: true)
        system("git", "clone", "-q", "--bare", work, remote, exception: true)
        yield dir, remote
      end
    end

    def push_commit(dir, remote, message)
      work = File.join(dir, "pusher")
      system("git", "clone", "-q", remote, work, exception: true) unless File.directory?(work)
      File.write(File.join(work, message), message)
      system("git", "-C", work, "add", ".", exception: true)
      system("git", "-C", work, "-c", "user.name=a", "-c", "user.email=a@b", "commit", "-qm", message, exception: true)
      system("git", "-C", work, "push", "-q", "origin", "main", exception: true)
    end

    def run_sync(remote, target, header: "Authorization: Basic X", branch: "main")
      @repository.source_branch = branch
      script = "set -e\n#{@setup.sync_script(@repository, target, "file://#{remote}")}"
      system({ "AIXLE_GIT_AUTH_HEADER" => header, "GIT_CONFIG_NOSYSTEM" => "1" }, "sh", "-c", script, out: File::NULL, err: File::NULL)
    end

    def git(path, *args) = IO.popen([ "git", "-C", path, *args ], err: File::NULL, &:read).strip

    def sha(path, rev) = git(path, "rev-parse", rev)

    def clone_script
      @runtime.execs.map { |cmd| Array(cmd).join(" ") }.find { |c| c.include?("clone --filter=blob:none") }
    end

    def git_clone_ran? = @runtime.execs.any? { |cmd| Array(cmd).join(" ").include?("clone --filter=blob:none") }
  end
end
