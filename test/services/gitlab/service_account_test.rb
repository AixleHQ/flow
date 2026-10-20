# frozen_string_literal: true

require "test_helper"

# A one-time OAuth consent spent on a service account
# (docs/design/gitlab-tracker.md §4): contract tests of Gitlab::Oauth and
# Gitlab::ServiceAccountSetup against GitLab's payloads, and the connection
# Gitlab::IntegrationService keeps afterwards.
class Gitlab::ServiceAccountTest < ActiveSupport::TestCase
  API = "https://gitlab.com/api/v4"

  setup do
    Settings.gitlab.stubs(:oauth_client_id).returns("gl-app")
    Settings.gitlab.stubs(:oauth_client_secret).returns("gl-secret")
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @service = Gitlab::IntegrationService.new(company: @company, connected_by: @user, project: @project)
  end

  def json(body, status: 200) = { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }

  def stub_consent(groups:, accounts: [])
    stub_request(:get, "#{API}/groups/31/service_accounts").with(query: hash_including("per_page" => "100")).to_return(json(accounts))
    stub_request(:post, "https://gitlab.com/oauth/token")
      .with(body: hash_including("grant_type" => "authorization_code", "code" => "c0de", "code_verifier" => "v3r"))
      .to_return(json({ access_token: "person-token", refresh_token: "r", expires_in: 7200 }))
    stub_request(:get, "#{API}/user").with(headers: { "Authorization" => "Bearer person-token" }).to_return(json({ id: 7, username: "owner" }))
    stub_request(:get, "#{API}/groups").with(query: hash_including("min_access_level" => "50")).to_return(json(groups))
  end

  test "the authorize URL asks for api with PKCE, and its state carries the verifier server-side" do
    uri = URI.parse(Gitlab::Oauth.authorize_url(project: @project, user: @user))
    query = Rack::Utils.parse_query(uri.query)
    state = Oauth::State.decode(query["state"])

    assert_equal [ "gitlab.com", "/oauth/authorize", "api", "S256", "gl-app" ],
                 [ uri.host, uri.path, query["scope"], query["code_challenge_method"], query["client_id"] ]
    verifier = Oauth::State.consume(state["nonce"])["code_verifier"]
    assert_equal Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false), query["code_challenge"]
  end

  test "a consent leaves a pending connection with the groups the person owns, and the group finishes it as the bot" do
    stub_consent(groups: [ { id: 31, full_path: "acme", full_name: "Acme", name: "Acme" } ])
    account = stub_request(:post, "#{API}/groups/31/service_accounts").with(headers: { "Authorization" => "Bearer person-token" })
                .to_return(json({ id: 900, username: "aixle-flow-ab12", name: "Aixle Flow" }, status: 201))
    member = stub_request(:post, "#{API}/groups/31/members").with(body: { user_id: 900, access_level: 40 }.to_json)
               .to_return(json({ id: 900 }, status: 201))
    stub_request(:post, "#{API}/groups/31/service_accounts/900/personal_access_tokens")
      .with(body: { name: "Aixle Flow", scopes: [ "api" ] }.to_json)
      .to_return(json({ id: 55, token: "glpat-bot", expires_at: "2027-10-20" }, status: 201))

    pending = @service.connect_oauth(code: "c0de", code_verifier: "v3r")
    assert_equal [ "inactive", "service_account_pending", [ "acme" ] ],
                 [ pending.status, pending.settings["auth_mode"], pending.settings["gitlab_groups"].pluck("full_path") ]

    connected = @service.create_service_account(pending, group_id: "31")

    assert_requested account
    assert_requested member
    assert_equal [ "active", "service_account", "aixle-flow-ab12", "acme", "2027-10-20" ],
                 [ connected.status.to_s, connected.settings["auth_mode"], connected.settings["gitlab_username"],
                   connected.settings.dig("gitlab_group", "full_path"), connected.settings["token_expires_at"] ]
    assert_equal({ "personal_access_token" => "glpat-bot", "service_account_token_id" => "55" }, connected.reload.credentials_data)
    assert_not connected.settings.key?("gitlab_groups")
  end

  test "reconnecting to a group reuses this deployment's account there, and revokes the token it replaces" do
    stale = create(:integration, :gitlab, :active, company: @company, project: @project)
    stale.credentials_data = { "personal_access_token" => "glpat-old" }
    stale.update!(settings: { "auth_mode" => "service_account", "gitlab_user_id" => "900", "gitlab_group" => { "id" => "31" } })
    stub_consent(groups: [ { id: 31, full_path: "acme", name: "Acme" } ],
                 accounts: [ { id: 800, username: "aixle-flow-0ld", name: "Aixle Flow" },
                             { id: 900, username: "aixle-flow-ab12", name: Gitlab::ServiceAccountSetup.account_name } ])
    stub_request(:post, "#{API}/groups/31/members").to_return(json({ message: "Member already exists" }, status: 409))
    stub_request(:post, "#{API}/groups/31/service_accounts/900/personal_access_tokens")
      .to_return(json({ id: 57, token: "glpat-new", expires_at: nil }, status: 201))
    revoked = stub_request(:delete, "#{API}/personal_access_tokens/self").with(headers: { "Authorization" => "Bearer glpat-old" })
                .to_return(status: 204)
    pending = @service.connect_oauth(code: "c0de", code_verifier: "v3r")

    connected = @service.create_service_account(pending, group_id: "31")

    assert_not_requested :post, "#{API}/groups/31/service_accounts"
    assert_requested revoked
    assert_equal [ stale.id, "900", "glpat-new" ],
                 [ connected.id, connected.settings["gitlab_user_id"], connected.reload.credentials_data["personal_access_token"] ]
    assert_not Integration.exists?(pending.id)
  end

  test "an account another connection runs as is not reused: that connection would lose its own token" do
    holder = create(:integration, :gitlab, :active, company: @company, project: create(:project, company: @company, owner: @user))
    holder.update!(settings: { "auth_mode" => "service_account", "gitlab_user_id" => "900" })
    stub_consent(groups: [ { id: 31, full_path: "acme", name: "Acme" } ],
                 accounts: [ { id: 900, username: "aixle-flow-ab12", name: Gitlab::ServiceAccountSetup.account_name } ])
    created = stub_request(:post, "#{API}/groups/31/service_accounts")
                .with(body: hash_including("name" => Gitlab::ServiceAccountSetup.account_name))
                .to_return(json({ id: 901, username: "aixle-flow-cd34", name: Gitlab::ServiceAccountSetup.account_name }, status: 201))
    stub_request(:post, "#{API}/groups/31/members").to_return(json({ id: 901 }, status: 201))
    stub_request(:post, "#{API}/groups/31/service_accounts/901/personal_access_tokens")
      .to_return(json({ id: 58, token: "glpat-second", expires_at: nil }, status: 201))
    pending = @service.connect_oauth(code: "c0de", code_verifier: "v3r")

    connected = @service.create_service_account(pending, group_id: "31")

    assert_requested created
    assert_equal "901", connected.settings["gitlab_user_id"]
  end

  test "someone who owns no group is told who has to connect" do
    stub_consent(groups: [])

    error = assert_raises(Gitlab::IntegrationService::ConnectionError) { @service.connect_oauth(code: "c0de", code_verifier: "v3r") }

    assert_match(/not an Owner of any GitLab group/, error.message)
    assert_equal 0, Integration.count
  end

  test "a group GitLab refuses the account in says what it takes" do
    stub_consent(groups: [ { id: 31, full_path: "acme", name: "Acme" } ])
    stub_request(:post, "#{API}/groups/31/service_accounts").to_return(json({ message: "403 Forbidden" }, status: 403))
    pending = @service.connect_oauth(code: "c0de", code_verifier: "v3r")

    error = assert_raises(Gitlab::IntegrationService::ConnectionError) { @service.create_service_account(pending, group_id: "31") }

    assert_match(/Owner role/, error.message)
    assert_equal "inactive", pending.reload.status
  end

  test "a token a month from its required expiry rotates itself for as long as the group allows" do
    integration = create(:integration, :gitlab, :active, company: @company, project: @project)
    integration.update!(settings: { "auth_mode" => "service_account", "token_expires_at" => 10.days.from_now.to_date.iso8601 })
    stub_request(:post, "#{API}/personal_access_tokens/self/rotate")
      .with(body: { expires_at: (Date.current + 365).iso8601 }.to_json).to_return(json({ message: "too long" }, status: 400))
    stub_request(:post, "#{API}/personal_access_tokens/self/rotate")
      .with(body: { expires_at: (Date.current + 180).iso8601 }.to_json)
      .to_return(json({ id: 56, token: "glpat-new", expires_at: (Date.current + 180).iso8601 }))

    assert Gitlab::ServiceAccountToken.due?(integration)
    Gitlab::ServiceAccountToken.rotate!(integration)

    assert_equal [ "glpat-new", (Date.current + 180).iso8601 ],
                 [ integration.reload.credentials_data["personal_access_token"], integration.settings["token_expires_at"] ]
  end
end
