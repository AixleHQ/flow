# frozen_string_literal: true

require "test_helper"

class Teams::ConnectionTest < ActiveSupport::TestCase
  GLOBAL_ADMIN = "62e90394-69f5-4237-9190-012177145e10"
  SIGN_IN_TOKEN_URL = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"

  setup do
    with_teams_enabled
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
  end

  def id_token(**claims)
    JWT.encode({ aud: TEAMS_APP_ID, tid: TEAMS_CUSTOMER_TENANT, oid: "0a1b", name: "Megan Bowen",
                 preferred_username: "megan@contoso.com", wids: [ GLOBAL_ADMIN ], exp: 1.hour.from_now.to_i }
               .merge(claims), "test", "HS256")
  end

  def stub_sign_in(**claims)
    stub_request(:post, SIGN_IN_TOKEN_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id_token: id_token(**claims), access_token: "unused" }.to_json)
  end

  def approve(integration, **claims)
    stub_sign_in(**claims)
    Teams::Connection.complete!(integration: integration, code: "code-1", code_verifier: "verifier-1")
  end

  test "a connection waits, company-wide and inactive, behind a link only its digest is kept for" do
    integration, token = Teams::Connection.start!(company: @company, user: @user)

    assert integration.teams?
    assert_equal "inactive", integration.status
    assert_nil integration.project_id
    assert_equal @user, integration.connected_by
    assert_not_includes integration.settings.to_json, token
    assert_equal integration, Teams::Connection.find_by_token(token)
    assert_nil Teams::Connection.find_by_token("not-#{token}")
  end

  test "asking again replaces the link of the connection still waiting" do
    first, old_token = Teams::Connection.start!(company: @company, user: @user)
    second, new_token = Teams::Connection.start!(company: @company, user: @user)

    assert_equal first, second
    assert_nil Teams::Connection.find_by_token(old_token)
    assert_equal first, Teams::Connection.find_by_token(new_token)
  end

  test "an approval link stops working after a week" do
    _integration, token = Teams::Connection.start!(company: @company, user: @user)

    travel 8.days do
      assert_nil Teams::Connection.find_by_token(token)
    end
  end

  test "an administrator's sign-in binds the organization it came from" do
    integration, = Teams::Connection.start!(company: @company, user: @user)

    approve(integration)

    integration.reload
    assert integration.active?
    assert_equal "Microsoft Teams (contoso.com)", integration.name
    assert_equal TEAMS_CUSTOMER_TENANT, integration.settings["tenant_id"]
    assert_equal({ "object_id" => "0a1b", "name" => "Megan Bowen", "username" => "megan@contoso.com",
                   "roles" => [ "Global Administrator" ] }, integration.settings["approved_by"])
    endpoint = WebhookEndpoint.find_by!(slug: "teams-tenant-#{TEAMS_CUSTOMER_TENANT}")
    assert_equal [ "teams", @company.id, integration.id ], [ endpoint.provider.to_s, endpoint.company_id,
                                                             endpoint.config["integration_id"] ]
    assert_requested(:post, SIGN_IN_TOKEN_URL) do |request|
      form = Rack::Utils.parse_query(request.body)
      form["code_verifier"] == "verifier-1" && form["client_assertion"].present? && form["client_secret"].nil?
    end
  end

  test "a sign-in without a directory administrator role binds nothing" do
    integration, = Teams::Connection.start!(company: @company, user: @user)

    error = assert_raises(Teams::Connection::Refused) { approve(integration, wids: [ "b79fbf4d-3ef9-4689-8143-76b194e85509" ]) }

    assert_match(/Megan Bowen is not an administrator/, error.message)
    assert_equal "inactive", integration.reload.status
    assert_not WebhookEndpoint.exists?(slug: "teams-tenant-#{TEAMS_CUSTOMER_TENANT}")
  end

  test "a sign-in issued to another application is refused" do
    integration, = Teams::Connection.start!(company: @company, user: @user)

    assert_raises(Teams::Connection::Refused) { approve(integration, aud: "another-app") }
    assert_equal "inactive", integration.reload.status
  end

  test "an organization belongs to one workspace" do
    approve(Teams::Connection.start!(company: @company, user: @user).first)
    other_company = create(:company)
    other, = Teams::Connection.start!(company: other_company, user: create(:user, :admin, company: other_company))

    error = assert_raises(Teams::Connection::Refused) { approve(other) }

    assert_match(/already connected/, error.message)
    assert_equal "inactive", other.reload.status
  end

  test "an installation pinned to its own organizations refuses any other" do
    Settings.teams.allowed_tenant_ids = TEAMS_HOME_TENANT
    integration, = Teams::Connection.start!(company: @company, user: @user)

    assert_raises(Teams::Connection::Refused) { approve(integration) }
  end

  test "disconnecting frees the organization for another workspace" do
    integration, = Teams::Connection.start!(company: @company, user: @user)
    approve(integration)

    integration.destroy!

    assert_not WebhookEndpoint.exists?(slug: "teams-tenant-#{TEAMS_CUSTOMER_TENANT}")
    other_company = create(:company)
    other, = Teams::Connection.start!(company: other_company, user: create(:user, :admin, company: other_company))
    assert approve(other).active?
  end

  test "file access is read from a token issued after the consent, not the cached one" do
    integration, = Teams::Connection.start!(company: @company, user: @user)
    approve(integration)
    stub_request(:post, "https://login.microsoftonline.com/#{TEAMS_CUSTOMER_TENANT}/oauth2/v2.0/token")
      .to_return({ status: 200, headers: { "Content-Type" => "application/json" },
                   body: { access_token: JWT.encode({ roles: [ "Group.Selected" ] }, "k", "HS256"), expires_in: 3600 }.to_json },
                 { status: 200, headers: { "Content-Type" => "application/json" },
                   body: { access_token: JWT.encode({ roles: [ "Group.Selected", "Files.ReadWrite.All" ] }, "k", "HS256"),
                           expires_in: 3600 }.to_json })
    Teams::TokenService.graph_token(TEAMS_CUSTOMER_TENANT)

    assert Teams::Connection.confirm_file_access!(integration)
    assert integration.reload.settings["file_access"]
  end

  test "the consent page is the organization's own" do
    integration, = Teams::Connection.start!(company: @company, user: @user)
    approve(integration)

    url = URI.parse(Teams::Connection.file_access_url(integration))

    assert_equal "/#{TEAMS_CUSTOMER_TENANT}/adminconsent", url.path
    assert_equal TEAMS_APP_ID, Rack::Utils.parse_query(url.query)["client_id"]
  end
end
