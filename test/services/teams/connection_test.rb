# frozen_string_literal: true

require "test_helper"

class Teams::ConnectionTest < ActiveSupport::TestCase
  GLOBAL_ADMIN = "62e90394-69f5-4237-9190-012177145e10"
  NOT_AN_ADMIN_ROLE = "b79fbf4d-3ef9-4689-8143-76b194e85509"
  SIGN_IN_TOKEN_URL = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"
  CATALOG = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps"

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
                 body: { id_token: id_token(**claims), access_token: "admin-graph-token" }.to_json)
  end

  def stub_catalog(existing: nil)
    stub_request(:get, %r{\A#{Regexp.escape(CATALOG)}\?})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [ existing ].compact }.to_json)
  end

  setup { stub_catalog && stub_request(:post, CATALOG).to_return(status: 201, body: { id: "app-1" }.to_json) }

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

  test "approving publishes the Teams app to the organization's catalog as the administrator" do
    integration, = Teams::Connection.start!(company: @company, user: @user)

    approve(integration)

    assert_requested(:post, SIGN_IN_TOKEN_URL) { |request| Rack::Utils.parse_query(request.body)["scope"].include?("AppCatalog.ReadWrite.All") }
    assert_requested(:post, CATALOG) do |request|
      request.headers["Authorization"] == "Bearer admin-graph-token" && request.headers["Content-Type"] == "application/zip" &&
        request.body.start_with?("PK")
    end
    assert_equal [ "app-1", Teams::AppPackage::VERSION, nil ],
                 integration.reload.settings.values_at("catalog_app_id", "catalog_version", "catalog_error")
  end

  test "an app already in the catalog is updated to a newer package, and left alone at the same version" do
    integration, = Teams::Connection.start!(company: @company, user: @user)
    stub_catalog(existing: { id: "app-9", appDefinitions: [ { version: "0.9.0" } ] })
    update = stub_request(:post, "#{CATALOG}/app-9/appDefinitions").to_return(status: 201, body: { teamsAppId: "app-9" }.to_json)

    approve(integration)
    assert_requested update, times: 1
    assert_equal "app-9", integration.reload.settings["catalog_app_id"]

    stub_catalog(existing: { id: "app-9", appDefinitions: [ { version: Teams::AppPackage::VERSION } ] })
    approve(integration)
    assert_requested update, times: 1
  end

  test "a role that cannot publish leaves the connection working and the package to upload" do
    stub_request(:post, CATALOG).to_return(status: 403, body: { error: { code: "Forbidden" } }.to_json)
    integration, = Teams::Connection.start!(company: @company, user: @user)

    approve(integration)

    assert integration.reload.active?
    assert_equal "forbidden", integration.settings["catalog_error"]
  end

  test "a sign-in without a directory administrator role binds nothing" do
    integration, = Teams::Connection.start!(company: @company, user: @user)

    error = assert_raises(Teams::Connection::Refused) { approve(integration, wids: [ NOT_AN_ADMIN_ROLE ]) }

    assert_match(/Megan Bowen is not an administrator/, error.message)
    assert_equal "inactive", integration.reload.status
    assert_not WebhookEndpoint.exists?(slug: "teams-tenant-#{TEAMS_CUSTOMER_TENANT}")
  end

  test "a sign-in issued to another application is refused" do
    integration, = Teams::Connection.start!(company: @company, user: @user)

    assert_raises(Teams::Connection::Refused) { approve(integration, aud: "another-app") }
    assert_equal "inactive", integration.reload.status
  end

  test "a connection's approval link can be renewed, and the old one stops working" do
    integration, old = Teams::Connection.start!(company: @company, user: @user)
    approve(integration)

    renewed = Teams::Connection.renew_link!(integration)

    assert_nil Teams::Connection.find_by_token(old)
    assert_equal integration, Teams::Connection.find_by_token(renewed)
    assert integration.reload.active?
  end

  test "a connected organization cannot be swapped for another through its link" do
    integration, = Teams::Connection.start!(company: @company, user: @user)
    approve(integration)

    error = assert_raises(Teams::Connection::Refused) { approve(integration, tid: "22222222-0000-4000-8000-0000000000dd") }

    assert_match(/already serves another/, error.message)
    assert_equal TEAMS_CUSTOMER_TENANT, integration.reload.settings["tenant_id"]
    assert_not WebhookEndpoint.exists?(slug: "teams-tenant-22222222-0000-4000-8000-0000000000dd")
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
