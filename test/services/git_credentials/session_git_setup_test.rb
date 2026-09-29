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

    test "installing the helper on its own says so when it cannot be written" do
      @runtime.fail_write(SessionGitSetup::HELPER)

      assert_raises(SessionGitSetup::HelperNotInstalled) { @setup.install_helper!(1001) }
    end

    private

    def git_clone_ran? = @runtime.execs.any? { |cmd| Array(cmd).join(" ").include?("clone --depth=1") }
  end
end
