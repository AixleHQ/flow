# frozen_string_literal: true

require "test_helper"

class InternalTools::GithubUserTokenTest < ActiveSupport::TestCase
  setup do
    @runtime = stub_container_runtime
    Settings.github.stubs(:client_id).returns("Iv1.client")
    Settings.github.stubs(:client_secret).returns("client-secret")

    @company = create(:company)
    @user = create(:user, :admin, company: @company, name: "Artem")
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    @integration = create(:integration, :github, :active, company: @company)
    @repository = create(:repository, scope: @project, integration: @integration, full_name: "AixleHQ/flow")
    @session.repositories << @repository
    @credential = create(:oauth_credential, :github_user, owner: @user)
    @fake = FakeGithub::UserTokenService.new
    Github::UserTokenService.stubs(:new).returns(@fake)
  end

  teardown { cleanup_runtime_overrides }

  def consent!(**flags)
    create(:act_as_consent, user: @user, project: @project, **flags)
  end

  def run_tool(session: @session)
    InternalTools::GithubUserToken.new(params: {}, session: session).execute
  end

  test "returns a scoped token and the commit identity of the session's user" do
    consent!(in_own_tasks: true)

    result = run_tool

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal({ "id" => @user.id, "name" => "Artem" }, payload["user"])
    assert_equal({ "login" => "octo-user", "github_id" => 123, "name" => "Octo User",
                   "email" => "123+octo-user@users.noreply.github.com" }, payload["identity"])
    token = payload["tokens"].sole
    assert_equal "ghu_fake_scoped_token", token["token"]
    assert_equal "AixleHQ", token["owner"]
    assert_equal [ "AixleHQ/flow" ], token["repositories"]
    assert_equal({ "contents" => "write", "pull_requests" => "write" }, token["permissions"])
    assert_equal [ "flow" ], @fake.calls_to(:scoped_token).sole[:repositories]
  end

  test "sends the stored user token to GitHub, never to the agent" do
    consent!(in_own_tasks: true)

    result = run_tool

    assert_equal @credential.access_token, @fake.calls_to(:scoped_token).sole[:user_token]
    assert_not_includes result[:stdout], @credential.access_token
  end

  test "records an issuance, arms the redaction list, and masks the token" do
    consent!(in_own_tasks: true)

    result = run_tool

    token = JSON.parse(result[:stdout])["tokens"].sole["token"]
    issuance = UserTokenIssuance.sole
    assert_equal token, issuance.token
    assert_equal @session, issuance.terminal_session
    assert_equal @user, issuance.acting_for_user
    assert_equal "github_user_token", issuance.tool_name
    assert_equal "AixleHQ", issuance.target_login
    assert_includes Sessions::SecretRegistry.new(@session, runtime: @runtime).send(:values), token
    assert_includes Sessions::SecretRedactor.secret_values_for(@session), token
  end

  test "refuses when the redaction list cannot be armed" do
    consent!(in_own_tasks: true)
    Sessions::SecretRegistry.stubs(:publish!).returns(false)

    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(/redaction could not be armed/, result[:stderr])
    assert_not_includes result.values.join, "ghu_fake_scoped_token"
  end

  test "one token per repository owner" do
    consent!(in_own_tasks: true)
    other = create(:repository, scope: @project, integration: @integration, full_name: "acme/tools")
    @session.repositories << other
    fake = FakeGithub::UserTokenService.new(tokens: %w[ghu_one ghu_two])
    Github::UserTokenService.stubs(:new).returns(fake)

    tokens = JSON.parse(run_tool[:stdout])["tokens"]

    assert_equal %w[AixleHQ acme], tokens.pluck("owner").sort
    assert_equal 2, UserTokenIssuance.count
  end

  test "lists a repository on a personal access token connection as skipped" do
    consent!(in_own_tasks: true)
    pat = create(:integration, :github_pat, :active, company: @company)
    @session.repositories << create(:repository, scope: @project, integration: pat, full_name: "AixleHQ/pat-repo")

    payload = JSON.parse(run_tool[:stdout])

    assert_equal [ "AixleHQ/flow" ], payload["tokens"].sole["repositories"]
    assert_equal "AixleHQ/pat-repo", payload["skipped"].sole["repository"]
  end

  test "errors when the session has no GitHub App repository" do
    consent!(in_own_tasks: true)
    @session.repositories.destroy_all

    assert_match(/no GitHub repositories/, run_tool[:stderr])
  end

  test "errors without consent" do
    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(/has not allowed agents to act as them in their own tasks/, result[:stderr])
    assert_empty @fake.calls
  end

  test "the other switch does not grant the own-tasks consent" do
    consent!(in_others_tasks: true)

    assert_match(/their own tasks/, run_tool[:stderr])
  end

  test "errors without a connected account" do
    @credential.destroy!
    consent!(in_own_tasks: true)

    assert_match(/has not connected a GitHub account/, run_tool[:stderr])
  end

  test "errors for a revoked connection" do
    @credential.update!(status: :revoked)
    consent!(in_own_tasks: true)

    assert_match(/has not connected a GitHub account/, run_tool[:stderr])
  end

  test "errors without a session user" do
    @session.stubs(:user).returns(nil)

    assert_match(/no user/, run_tool[:stderr])
  end

  test "errors when the user is no longer a member of the project" do
    consent!(in_own_tasks: true)
    @company.company_memberships.find_by(user: @user).update!(state: "suspended")

    assert_match(/is not a member of project/, run_tool[:stderr])
  end

  test "asks to reconnect when GitHub no longer accepts the stored token" do
    consent!(in_own_tasks: true)
    Github::UserTokenService.stubs(:new).returns(FakeGithub::UserTokenService.new(scoped_error: Github::UserTokenService::InvalidToken.new("x")))

    result = run_tool

    assert_match(/needs to be renewed/, result[:stderr])
    assert_equal 1, @credential.reload.refresh_failure_count
  end

  test "reports a refusal by GitHub without its body" do
    consent!(in_own_tasks: true)
    Github::UserTokenService.stubs(:new).returns(FakeGithub::UserTokenService.new(scoped_error: Github::UserTokenService::Forbidden.new("ghu_leak")))

    result = run_tool

    assert_match(/GitHub refused access to AixleHQ\/flow for octo-user/, result[:stderr])
    assert_not_includes result[:stderr], "ghu_leak"
  end

  test "asks to reconnect when the connection can no longer be refreshed" do
    consent!(in_own_tasks: true)
    @credential.update!(expires_at: 1.minute.ago, refresh_token: nil)

    assert_match(/needs to be renewed/, run_tool[:stderr])
  end

  test "is unavailable where the GitHub App's client credentials are not set" do
    Settings.github.stubs(:client_id).returns("")
    definition = InternalTools::GithubUserToken.tool_definition

    assert_not definition.available?(Tools::Context.new(company: @company, project: @project))
  end
end
