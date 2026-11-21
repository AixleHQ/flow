# frozen_string_literal: true

require "test_helper"

class InternalTools::BitbucketUserTokenTest < ActiveSupport::TestCase
  include BitbucketTestHelper

  setup do
    @runtime = stub_container_runtime
    Settings.bitbucket.oauth.stubs(:client_id).returns("bb-cid")
    Settings.bitbucket.oauth.stubs(:client_secret).returns("bb-secret")

    @company = create(:company)
    @user = create(:user, :admin, company: @company, name: "Artem")
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    @integration = create(:integration, :bitbucket, :active, company: @company, project: @project)
    @repository = create(:repository, :bitbucket, scope: @project, integration: @integration, full_name: "acme/api")
    @session.repositories << @repository
    @credential = create(:oauth_credential, :bitbucket_user, owner: @user)
    @fake = stub_bitbucket!
    @fake.user = { uuid: "{6c1f0a4e-0000-4000-8000-0000000000b1}", account_id: "712020:abc", display_name: "Bee Bucket",
                   nickname: "bb-user", avatar_url: "https://a.test/bb" }
    @fake.permissions = { "acme/api" => "write" }
  end

  teardown { cleanup_runtime_overrides }

  def consent!(**flags)
    create(:act_as_consent, user: @user, project: @project, provider: "bitbucket", **flags)
  end

  def run_tool(session: @session)
    InternalTools::BitbucketUserToken.new(params: {}, session: session).execute
  end

  test "returns the person's token and the commit identity from their confirmed address" do
    consent!(in_own_tasks: true)

    result = run_tool

    assert_equal 0, result[:exit_code]
    payload = JSON.parse(result[:stdout])
    assert_equal({ "id" => @user.id, "name" => "Artem" }, payload["user"])
    assert_equal({ "login" => "bb-user", "bitbucket_uuid" => "{6c1f0a4e-0000-4000-8000-0000000000b1}",
                   "name" => "Bee Bucket", "email" => "bee@example.com" }, payload["identity"])
    token = payload["tokens"].sole
    assert_equal @credential.access_token, token["token"]
    assert_equal "https://bitbucket.org", token["host"]
    assert_equal "https://api.bitbucket.org/2.0", token["api_url"]
    assert_equal %w[account email repository repository:write pullrequest pullrequest:write], token["scopes"]
    assert_equal "x-token-auth", token["git_username"]
    assert_equal [ "acme/api" ], token["repositories"]
    assert_empty payload["skipped"]
    assert_match(/not limited to these repositories/, payload["note"])
  end

  test "reports the expiry minus the refresh skew, the moment to ask again" do
    consent!(in_own_tasks: true)

    token = JSON.parse(run_tool[:stdout])["tokens"].sole

    assert_in_delta (@credential.expires_at - Oauth::TokenService::REFRESH_SKEW).to_f, Time.zone.parse(token["expires_at"]).to_f, 1
  end

  test "checks write access with the person's token, once for all repositories" do
    consent!(in_own_tasks: true)

    run_tool

    assert_equal [ "acme/api" ], @fake.calls_to(:repository_permissions).sole[:full_names]
  end

  test "an admin of the repository is covered too" do
    consent!(in_own_tasks: true)
    @fake.permissions = { "acme/api" => "admin" }

    assert_equal [ "acme/api" ], JSON.parse(run_tool[:stdout])["tokens"].sole["repositories"]
  end

  test "records one issuance, arms the redaction list and masks the token" do
    consent!(in_own_tasks: true)

    result = run_tool

    token = JSON.parse(result[:stdout])["tokens"].sole["token"]
    issuance = UserTokenIssuance.sole
    assert_equal token, issuance.token
    assert_equal "bitbucket", issuance.provider
    assert_equal "bitbucket_user_token", issuance.tool_name
    assert_equal @user, issuance.acting_for_user
    assert_equal @credential, issuance.oauth_credential
    assert_equal "bitbucket.org", issuance.target_login
    assert_equal [ "acme/api" ], issuance.repository_full_names
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

  test "lists a repository the person can only read as skipped" do
    consent!(in_own_tasks: true)
    @session.repositories << create(:repository, :bitbucket, scope: @project, integration: @integration, full_name: "acme/readonly")
    @fake.permissions = { "acme/api" => "write", "acme/readonly" => "read" }

    payload = JSON.parse(run_tool[:stdout])

    assert_equal [ "acme/api" ], payload["tokens"].sole["repositories"]
    assert_equal [ { "repository" => "acme/readonly", "reason" => "Artem cannot push to it" } ], payload["skipped"]
  end

  test "a repository the person has no permission on is skipped, not covered" do
    consent!(in_own_tasks: true)
    @session.repositories << create(:repository, :bitbucket, scope: @project, integration: @integration, full_name: "acme/hidden")

    payload = JSON.parse(run_tool[:stdout])

    assert_equal "acme/hidden", payload["skipped"].sole["repository"]
  end

  test "refuses, naming the repositories, when the person can push to none" do
    consent!(in_own_tasks: true)
    @fake.permissions = { "acme/api" => "read" }

    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(%r{Artem cannot push to acme/api on Bitbucket}, result[:stderr])
    assert_equal 0, UserTokenIssuance.count
  end

  test "a repository whose permission list was cut short is skipped as unchecked, not as one the person cannot push to" do
    consent!(in_own_tasks: true)
    @session.repositories << create(:repository, :bitbucket, scope: @project, integration: @integration, full_name: "acme/deep")
    @fake.permissions = { "acme/api" => "write" }
    @fake.unchecked_permissions = [ "acme/deep" ]

    payload = JSON.parse(run_tool[:stdout])

    assert_equal [ "acme/api" ], payload["tokens"].sole["repositories"]
    assert_equal "acme/deep", payload["skipped"].sole["repository"]
    assert_match(/too long to read in full/, payload["skipped"].sole["reason"])
    assert_no_match(/cannot push/, payload["skipped"].sole["reason"])
  end

  test "refuses with a could-not-check error, not a cannot-push one, when nothing could be checked" do
    consent!(in_own_tasks: true)
    @fake.unchecked_permissions = [ "acme/api" ]

    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(%r{Could not check whether Artem can push to acme/api}, result[:stderr])
    assert_no_match(/cannot push/, result[:stderr])
    assert_equal 0, UserTokenIssuance.count
  end

  test "covers a repository of an app-mode integration as well" do
    consent!(in_own_tasks: true)
    app_integration = create(:integration, :bitbucket_app, :active, company: @company, project: @project)
    @session.repositories << create(:repository, :bitbucket, scope: @project, integration: app_integration, full_name: "acme/other")
    @fake.permissions = { "acme/api" => "write", "acme/other" => "write" }

    repositories = JSON.parse(run_tool[:stdout])["tokens"].sole["repositories"]

    assert_equal [ "acme/api", "acme/other" ], repositories.sort
  end

  test "an inactive Bitbucket connection's repository is skipped" do
    consent!(in_own_tasks: true)
    inactive = create(:integration, :bitbucket, company: @company, project: @project, status: :inactive)
    @session.repositories << create(:repository, :bitbucket, scope: @project, integration: inactive, full_name: "acme/idle")

    payload = JSON.parse(run_tool[:stdout])

    assert_equal [ "acme/api" ], payload["tokens"].sole["repositories"]
    assert_equal "acme/idle", payload["skipped"].sole["repository"]
  end

  test "errors when the session has no Bitbucket repository" do
    consent!(in_own_tasks: true)
    @session.repositories.destroy_all

    assert_match(/no Bitbucket repositories on an active Bitbucket connection/, run_tool[:stderr])
  end

  test "errors without consent, and the other switch does not grant it" do
    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(/has not allowed agents to act as them in their own tasks/, result[:stderr])
    assert_empty @fake.calls_to(:repository_permissions)

    consent!(in_others_tasks: true)

    assert_match(/their own tasks/, run_tool[:stderr])
  end

  test "a GitLab consent does not allow Bitbucket" do
    create(:act_as_consent, :own, user: @user, project: @project, provider: "gitlab")

    assert_match(/has not allowed agents to act as them/, run_tool[:stderr])
  end

  test "errors without a connected, or with a revoked, account" do
    consent!(in_own_tasks: true)
    @credential.update!(status: :revoked)

    assert_match(/has not connected a Bitbucket account/, run_tool[:stderr])

    @credential.destroy!

    assert_match(/has not connected a Bitbucket account/, run_tool[:stderr])
  end

  test "errors without a session user" do
    @session.stubs(:user).returns(nil)

    assert_match(/no user/, run_tool[:stderr])
  end

  test "refuses with a message about the email when the account has no confirmed address" do
    consent!(in_own_tasks: true)
    @credential.update!(metadata: { "bitbucket_user" => @credential.metadata["bitbucket_user"].merge("commit_email" => nil) })
    @fake.emails = [ { email: "unconfirmed@example.com", is_primary: true, is_confirmed: false } ]

    result = run_tool

    assert_equal 1, result[:exit_code]
    assert_match(/no confirmed primary email address/, result[:stderr])
    assert_equal 0, UserTokenIssuance.count
  end

  test "refetches an identity that a failed reconnect cleared" do
    consent!(in_own_tasks: true)
    @credential.update!(metadata: {})
    @fake.emails = [ { email: "other@example.com", is_primary: false, is_confirmed: true },
                     { email: "bee@example.com", is_primary: true, is_confirmed: true } ]

    payload = JSON.parse(run_tool[:stdout])

    assert_equal "bb-user", payload.dig("identity", "login")
    assert_equal "bee@example.com", payload.dig("identity", "email")
  end

  test "asks to reconnect on a 401, counting the failure, and never repeats a token or body" do
    consent!(in_own_tasks: true)
    @fake.fail_on(:repository_permissions, Bitbucket::Error::NotAuthorized.new("bb-leak"))

    result = run_tool

    assert_match(/needs to be renewed/, result[:stderr])
    assert_not_includes result[:stderr], "bb-leak"
    assert_equal 1, @credential.reload.refresh_failure_count
    assert @credential.active?
    assert_equal 0, UserTokenIssuance.count
  end

  test "the third consecutive 401 marks the credential as needing a reconnect" do
    consent!(in_own_tasks: true)
    @credential.update!(refresh_failure_count: OauthCredential::MAX_REFRESH_FAILURES - 1)
    @fake.fail_on(:repository_permissions, Bitbucket::Error::NotAuthorized.new)

    run_tool

    assert @credential.reload.error?
  end

  test "says Bitbucket is unavailable without its body, also for a rate limit" do
    consent!(in_own_tasks: true)
    @fake.fail_on(:repository_permissions, Bitbucket::Error::RateLimited.new("bb-leak"))

    result = run_tool

    assert_match(/Bitbucket is unavailable/, result[:stderr])
    assert_not_includes result[:stderr], "bb-leak"
    assert_equal 0, @credential.reload.refresh_failure_count
  end

  test "refreshes a token within the refresh skew of expiry before handing it out" do
    consent!(in_own_tasks: true)
    @credential.update!(expires_at: 5.minutes.from_now, refresh_token: "bb_old")
    stub_request(:post, "https://bitbucket.org/site/oauth2/access_token")
      .with(basic_auth: [ @credential.oauth_client.client_id, "secret" ])
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { access_token: "bb_refreshed", refresh_token: "bb_new", expires_in: 7200, scopes: "account" }.to_json)
    @credential.oauth_client.update!(client_secret: "secret")

    token = JSON.parse(run_tool[:stdout])["tokens"].sole

    assert_equal "bb_refreshed", token["token"]
  end

  test "does not refresh early: a token with more than the refresh skew left is handed out as it is" do
    consent!(in_own_tasks: true)
    @credential.update!(expires_at: 20.minutes.from_now)

    token = JSON.parse(run_tool[:stdout])["tokens"].sole

    assert_equal @credential.access_token, token["token"]
    assert_not_requested :post, "https://bitbucket.org/site/oauth2/access_token"
  end

  test "asks to reconnect when a short-lived token cannot be refreshed" do
    consent!(in_own_tasks: true)
    @credential.update!(expires_at: 5.minutes.from_now, refresh_token: nil)

    assert_match(/needs to be renewed/, run_tool[:stderr])
    assert_empty @fake.calls_to(:repository_permissions)
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

  test "is unavailable where the Bitbucket OAuth client is not set" do
    Settings.bitbucket.oauth.stubs(:client_id).returns("")
    definition = InternalTools::BitbucketUserToken.tool_definition

    assert_not definition.available?(Tools::Context.new(company: @company, project: @project))
  end
end
