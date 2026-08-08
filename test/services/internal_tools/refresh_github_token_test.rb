# frozen_string_literal: true

require "test_helper"

class InternalTools::RefreshGithubTokenTest < ActiveSupport::TestCase
  setup do
    @company     = create(:company)
    @user        = create(:user, :admin, company: @company)
    @project     = create(:project, company: @company, owner: @user)
    @integration = create(:integration, company: @company, connected_by: @user, status: :active)
    @repo        = create(:repository, full_name: "acme/my-app", integration: @integration, scope: @project)
    @session     = create(:terminal_session, :agent_session, :running, user: @user, project: @project,
                          agent_type: "claude_code")
    @session.repositories << @repo

    @runtime = stub_container_runtime
    @tokens  = FakeGithub::TokenService.new(token: "ghs_fresh")
    Github::TokenService.stubs(:new).returns(@tokens)
  end

  teardown { cleanup_runtime_overrides }

  def run_tool(params = {})
    InternalTools::RefreshGithubToken.new(params: params, session: @session).execute
  end

  test "re-points origin at a freshly minted token scoped to the repository" do
    result = run_tool

    assert_equal 0, result[:exit_code]

    command = @runtime.execs.last.last
    assert_match(%r{git -c safe\.directory=/workspace/repo/my-app -C /workspace/repo/my-app}, command)
    assert_match(%r{remote set-url origin.*x-access-token:ghs_fresh@github\.com/acme/my-app\.git}, command)
    assert_match(%r{chown 1001:1001 /workspace/repo/my-app/\.git/config}, command)

    assert_equal [ { repositories: [ "my-app" ] } ],
                 @tokens.calls_to(:generate_installation_token).map { |c| c.except(:method) }

    payload = JSON.parse(result[:stdout])
    assert_equal [ "acme/my-app" ], payload["refreshed"].map { |r| r["repository"] }
    assert_empty payload["failed"]
    assert_not_includes result[:stdout], "ghs_fresh"
  end

  test "refreshes every attached GitHub repository by default" do
    other = create(:repository, full_name: "acme/infra", integration: @integration, scope: @project)
    @session.repositories << other

    result = run_tool
    payload = JSON.parse(result[:stdout])

    assert_equal %w[acme/infra acme/my-app], payload["refreshed"].map { |r| r["repository"] }.sort
    assert_equal 2, @runtime.execs.size
  end

  test "the repository argument narrows the refresh to one clone, by full name or bare name" do
    other = create(:repository, full_name: "acme/infra", integration: @integration, scope: @project)
    @session.repositories << other

    payload = JSON.parse(run_tool("repository" => "acme/infra")[:stdout])
    assert_equal [ "acme/infra" ], payload["refreshed"].map { |r| r["repository"] }

    payload = JSON.parse(run_tool("repository" => "my-app")[:stdout])
    assert_equal [ "acme/my-app" ], payload["refreshed"].map { |r| r["repository"] }
  end

  test "an unknown repository argument lists what is actually attached" do
    result = run_tool("repository" => "acme/nope")

    assert_equal 1, result[:exit_code]
    assert_match(/No GitHub repository matching acme\/nope/, result[:stderr])
    assert_match(/acme\/my-app/, result[:stderr])
  end

  test "errors when the session has no container to re-point" do
    @session.update!(container_id: nil)

    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(/no running container/, result[:stderr])
    assert_empty @runtime.execs
  end

  test "public and GitLab clones carry no expiring token, so there is nothing to refresh" do
    @session.repositories.destroy_all
    gitlab = create(:integration, :gitlab, :active, company: @company, connected_by: @user)
    @session.repositories << create(:repository, full_name: "acme/gl", integration: gitlab, scope: @project,
                                    clone_url: "https://gitlab.com/acme/gl.git")
    @session.repositories << create(:repository, :public_source, full_name: "torvalds/linux", scope: @project,
                                    clone_url: "https://github.com/torvalds/linux.git")

    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(/No GitHub repository is attached/, result[:stderr])
    assert_empty @runtime.execs
  end

  test "a repository whose token cannot be minted fails alone and does not stop the others" do
    other = create(:repository, full_name: "acme/gone", integration: @integration, scope: @project)
    @session.repositories << other
    @tokens = FakeGithub::TokenService.new(token: "ghs_fresh", unreachable: [ "gone" ])
    Github::TokenService.stubs(:new).returns(@tokens)

    result = run_tool
    payload = JSON.parse(result[:stdout])

    assert_equal 0, result[:exit_code]
    assert_equal [ "acme/my-app" ], payload["refreshed"].map { |r| r["repository"] }
    assert_equal [ "acme/gone" ], payload["failed"].map { |r| r["repository"] }
    assert_match(/does not exist or is not accessible/, payload["failed"].first["error"])
  end

  test "an inactive integration is reported rather than called" do
    @integration.update!(status: :inactive)

    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(/integration is not active/, result[:stderr])
    assert_not @tokens.called?(:generate_installation_token)
    assert_empty @runtime.execs
  end

  test "a failing git command surfaces its stderr with the token redacted" do
    @runtime.fail_exec("remote set-url", stderr: "fatal: 'origin' does not appear to be a git repository ghs_fresh", exit_code: 128)

    result = run_tool

    assert_equal 1, result[:exit_code]
    payload = JSON.parse(result[:stderr])
    assert_equal [ "acme/my-app" ], payload["failed"].map { |r| r["repository"] }
    assert_match(/exited with 128/, payload["failed"].first["error"])
    assert_match(/\[REDACTED\]/, payload["failed"].first["error"])
    assert_not_includes result[:stderr], "ghs_fresh"
  end
end
