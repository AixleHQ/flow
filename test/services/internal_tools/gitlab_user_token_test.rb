# frozen_string_literal: true

require "test_helper"

class InternalTools::GitlabUserTokenTest < ActiveSupport::TestCase
  setup do
    @runtime = stub_container_runtime
    Settings.gitlab.stubs(:oauth_client_id).returns("lab-cid")
    Settings.gitlab.stubs(:oauth_client_secret).returns("lab-secret")

    @company = create(:company)
    @user = create(:user, :admin, company: @company, name: "Artem")
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    @integration = create(:integration, :gitlab, :active, company: @company)
    @repository = create(:repository, scope: @project, integration: @integration, full_name: "group/sub/app")
    @session.repositories << @repository
    @credential = create(:oauth_credential, :gitlab_user, owner: @user)
    use_fake!
  end

  teardown { cleanup_runtime_overrides }

  def use_fake!(**options)
    @fake = FakeGitlab::UserTokenService.new(**options)
    Gitlab::UserTokenService.stubs(:new).returns(@fake)
  end

  def consent!(**flags)
    create(:act_as_consent, user: @user, project: @project, provider: "gitlab", **flags)
  end

  def run_tool(session: @session)
    InternalTools::GitlabUserToken.new(params: {}, session: session).execute
  end

  test "returns the person's token and the commit identity GitLab itself uses" do
    consent!(in_own_tasks: true)

    result = run_tool

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal({ "id" => @user.id, "name" => "Artem" }, payload["user"])
    assert_equal({ "login" => "lab-user", "gitlab_id" => 456, "name" => "Lab User",
                   "email" => "456-lab-user@users.noreply.gitlab.com" }, payload["identity"])
    token = payload["tokens"].sole
    assert_equal @credential.access_token, token["token"]
    assert_equal Gitlab::Host.web_base, token["host"]
    assert_equal Gitlab::Host.api_endpoint, token["api_url"]
    assert_equal %w[api], token["scopes"]
    assert_equal "oauth2", token["git_username"]
    assert_equal [ "group/sub/app" ], token["repositories"]
    assert_empty payload["skipped"]
    assert_match(/not limited to these repositories/, payload["note"])
  end

  test "reports the expiry minus the refresh skew, the moment to ask again" do
    consent!(in_own_tasks: true)

    token = JSON.parse(run_tool[:stdout])["tokens"].sole

    assert_in_delta (@credential.expires_at - Oauth::TokenService::REFRESH_SKEW).to_f, Time.zone.parse(token["expires_at"]).to_f, 1
  end

  test "falls back to GitLab's noreply address when no commit email is stored" do
    consent!(in_own_tasks: true)
    @credential.update!(metadata: { "gitlab_user" => { "id" => 456, "username" => "lab-user", "name" => "Lab User",
                                                      "fetched_at" => Time.current.iso8601 } })

    email = JSON.parse(run_tool[:stdout]).dig("identity", "email")

    assert_equal "456-lab-user@users.noreply.#{URI.parse(Gitlab::Host.web_base).host}", email
  end

  test "checks push access with the person's token, passing their id for the member lookup" do
    consent!(in_own_tasks: true)

    run_tool

    call = @fake.calls_to(:project_access).sole
    assert_equal @credential.access_token, call[:token]
    assert_equal "group/sub/app", call[:full_path]
    assert_equal 456, call[:user_id]
  end

  test "records one issuance, arms the redaction list and masks the token" do
    consent!(in_own_tasks: true)

    result = run_tool

    token = JSON.parse(result[:stdout])["tokens"].sole["token"]
    issuance = UserTokenIssuance.sole
    assert_equal token, issuance.token
    assert_equal "gitlab", issuance.provider
    assert_equal "gitlab_user_token", issuance.tool_name
    assert_equal @user, issuance.acting_for_user
    assert_equal @credential, issuance.oauth_credential
    assert_equal URI.parse(Gitlab::Host.web_base).host, issuance.target_login
    assert_equal [ "group/sub/app" ], issuance.repository_full_names
    assert_includes Sessions::SecretRedactor.secret_values_for(@session), token
  end

  test "refuses when the redaction list cannot be armed" do
    consent!(in_own_tasks: true)
    Sessions::SecretRegistry.stubs(:publish!).returns(false)

    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(/redaction could not be armed/, result[:stderr])
    assert_not_includes result.values.join, @credential.access_token
  end

  test "lists a repository the person cannot push to as skipped" do
    consent!(in_own_tasks: true)
    other = create(:repository, scope: @project, integration: @integration, full_name: "group/readonly")
    @session.repositories << other
    use_fake!(access: { "group/readonly" => 20 })

    payload = JSON.parse(run_tool[:stdout])

    assert_equal [ "group/sub/app" ], payload["tokens"].sole["repositories"]
    assert_equal [ { "repository" => "group/readonly", "reason" => "Artem cannot push to it" } ], payload["skipped"]
  end

  test "a repository GitLab does not show the person is skipped, not covered" do
    consent!(in_own_tasks: true)
    other = create(:repository, scope: @project, integration: @integration, full_name: "group/hidden")
    @session.repositories << other
    use_fake!(access: { "group/hidden" => nil })

    payload = JSON.parse(run_tool[:stdout])

    assert_equal "group/hidden", payload["skipped"].sole["repository"]
  end

  test "refuses, naming the repositories, when the person can push to none" do
    consent!(in_own_tasks: true)
    use_fake!(access: { "group/sub/app" => 20 })

    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(%r{Artem cannot push to group/sub/app}, result[:stderr])
    assert_equal 0, UserTokenIssuance.count
  end

  test "covers a repository on a service-account connection as well" do
    consent!(in_own_tasks: true)
    other_integration = create(:integration, :gitlab, :active, company: @company)
    @session.repositories << create(:repository, scope: @project, integration: other_integration, full_name: "group/other")

    repositories = JSON.parse(run_tool[:stdout])["tokens"].sole["repositories"]

    assert_equal [ "group/sub/app", "group/other" ].sort, repositories.sort
  end

  test "an inactive GitLab connection's repository is skipped" do
    consent!(in_own_tasks: true)
    inactive = create(:integration, :gitlab, company: @company, status: :inactive)
    @session.repositories << create(:repository, scope: @project, integration: inactive, full_name: "group/idle")

    payload = JSON.parse(run_tool[:stdout])

    assert_equal [ "group/sub/app" ], payload["tokens"].sole["repositories"]
    assert_equal "group/idle", payload["skipped"].sole["repository"]
  end

  test "errors when the session has no GitLab repository" do
    consent!(in_own_tasks: true)
    @session.repositories.destroy_all

    assert_match(/no GitLab repositories on an active GitLab connection/, run_tool[:stderr])
  end

  test "errors without consent, and the other switch does not grant it" do
    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(/has not allowed agents to act as them in their own tasks/, result[:stderr])
    assert_empty @fake.calls

    consent!(in_others_tasks: true)

    assert_match(/their own tasks/, run_tool[:stderr])
  end

  test "a GitHub consent does not allow GitLab" do
    create(:act_as_consent, :own, user: @user, project: @project, provider: "github")

    assert_match(/has not allowed agents to act as them/, run_tool[:stderr])
  end

  test "errors without a connected, or with a revoked, account" do
    consent!(in_own_tasks: true)
    @credential.update!(status: :revoked)

    assert_match(/has not connected a GitLab account/, run_tool[:stderr])

    @credential.destroy!

    assert_match(/has not connected a GitLab account/, run_tool[:stderr])
  end

  test "ignores a connection made against another GitLab host" do
    consent!(in_own_tasks: true)
    @credential.oauth_client.update!(issuer: "https://old.gitlab.example.com")

    assert_match(/has not connected a GitLab account/, run_tool[:stderr])
  end

  test "errors without a session user" do
    @session.stubs(:user).returns(nil)

    assert_match(/no user/, run_tool[:stderr])
  end

  test "errors when the user is no longer a member of the project" do
    consent!(in_own_tasks: true)
    create(:user, :admin, company: @company)
    @company.company_memberships.find_by(user: @user).update!(state: "suspended")

    assert_match(/is not a member of project/, run_tool[:stderr])
  end

  test "asks to reconnect, and marks the credential, when GitLab rejects the token" do
    consent!(in_own_tasks: true)
    use_fake!(access_error: Gitlab::UserTokenService::InvalidToken.new("glo-leak"))

    result = run_tool

    assert_match(/needs to be renewed/, result[:stderr])
    assert_not_includes result[:stderr], "glo-leak"
    assert_equal 1, @credential.reload.refresh_failure_count
    assert_equal 0, UserTokenIssuance.count
  end

  test "says GitLab is unavailable without its body" do
    consent!(in_own_tasks: true)
    use_fake!(access_error: Gitlab::UserTokenService::Unavailable.new("glo-leak"))

    result = run_tool

    assert_match(/GitLab is unavailable/, result[:stderr])
    assert_not_includes result[:stderr], "glo-leak"
  end

  test "refreshes a token within the refresh skew of expiry before handing it out" do
    consent!(in_own_tasks: true)
    @credential.update!(expires_at: 5.minutes.from_now, refresh_token: "glr_old")
    stub_request(:post, "#{Gitlab::Host.web_base}/oauth/token")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { access_token: "glo_refreshed", refresh_token: "glr_new", expires_in: 7200 }.to_json)

    token = JSON.parse(run_tool[:stdout])["tokens"].sole

    assert_equal "glo_refreshed", token["token"]
    assert_equal "glo_refreshed", @fake.calls_to(:project_access).sole[:token]
  end

  test "does not refresh early: a token with more than the refresh skew left is handed out as it is" do
    consent!(in_own_tasks: true)
    @credential.update!(expires_at: 20.minutes.from_now)

    token = JSON.parse(run_tool[:stdout])["tokens"].sole

    assert_equal @credential.access_token, token["token"]
    assert_not_requested :post, "#{Gitlab::Host.web_base}/oauth/token"
  end

  test "asks to reconnect when a short-lived token cannot be refreshed" do
    consent!(in_own_tasks: true)
    @credential.update!(expires_at: 5.minutes.from_now, refresh_token: nil)

    assert_match(/needs to be renewed/, run_tool[:stderr])
    assert_empty @fake.calls_to(:project_access)
  end

  test "two sessions of one person receive the same token value, each with its own issuance" do
    consent!(in_own_tasks: true)
    second = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    second.repositories << @repository

    first_token = JSON.parse(run_tool[:stdout])["tokens"].sole["token"]
    second_token = JSON.parse(run_tool(session: second)[:stdout])["tokens"].sole["token"]

    assert_equal first_token, second_token
    assert_equal 2, UserTokenIssuance.count
  end

  test "refuses before handing out a token when the identity is unknown" do
    consent!(in_own_tasks: true)
    @credential.update!(metadata: {})
    use_fake!(profile_error: Gitlab::UserTokenService::Unavailable.new("x"))

    result = run_tool

    assert_match(/did not return this account's identity/, result[:stderr])
    assert_equal 0, UserTokenIssuance.count
  end

  test "refetches an identity that a failed reconnect cleared" do
    consent!(in_own_tasks: true)
    @credential.update!(metadata: {})

    assert_equal "lab-user", JSON.parse(run_tool[:stdout]).dig("identity", "login")
  end

  test "is unavailable where the GitLab OAuth app is not set" do
    Settings.gitlab.stubs(:oauth_client_id).returns("")
    definition = InternalTools::GitlabUserToken.tool_definition

    assert_not definition.available?(Tools::Context.new(company: @company, project: @project))
  end
end
