# frozen_string_literal: true

require "test_helper"

# The page a Microsoft 365 administrator opens from an approval link, through
# Microsoft's sign-in and admin consent. Entra is WebMock-stubbed; the signed
# OAuth state round-trips through a real cache.
class Web::Integrations::TeamsApprovalTest < ActionDispatch::IntegrationTest
  GLOBAL_ADMIN = "62e90394-69f5-4237-9190-012177145e10"

  setup do
    with_teams_enabled
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @company = create(:company, name: "Acme")
    @user = create(:user, :admin, company: @company, name: "Ada Lovelace")
    @integration, @token = Teams::Connection.start!(company: @company, user: @user)
  end

  def stub_sign_in(wids: [ GLOBAL_ADMIN ])
    claims = { aud: TEAMS_APP_ID, tid: TEAMS_CUSTOMER_TENANT, oid: "0a1b", name: "Megan Bowen",
               preferred_username: "megan@contoso.com", wids: wids, exp: 1.hour.from_now.to_i }
    stub_request(:post, "https://login.microsoftonline.com/organizations/oauth2/v2.0/token")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id_token: JWT.encode(claims, "test", "HS256") }.to_json)
  end

  def sign_in_state
    get teams_approval_sign_in_path(@token)
    Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
  end

  test "the administrator needs no Aixle account to see who asked to connect what" do
    get teams_approval_path(@token)

    assert_inertia_page "Integrations/TeamsApproval"
    assert_inertia_props do |props|
      props[:state] == "pending" && props[:workspace] == "Acme" && props[:requestedBy][:name] == "Ada Lovelace" &&
        props[:signInUrl] == teams_approval_sign_in_path(@token)
    end
  end

  test "a link that does not open a waiting connection says it is no longer valid" do
    get teams_approval_path("unknown")

    assert_inertia_page "Integrations/TeamsApproval"
    assert_inertia_props { |props| props[:state] == "expired" && !props.key?(:workspace) }
  end

  test "signing in as a directory administrator connects the organization and offers the app" do
    get teams_approval_path(@token)
    get teams_approval_sign_in_path(@token)
    authorize = URI.parse(response.location)
    query = Rack::Utils.parse_query(authorize.query)
    assert_equal [ "login.microsoftonline.com", "/organizations/oauth2/v2.0/authorize" ], [ authorize.host, authorize.path ]
    assert_equal [ TEAMS_APP_ID, "S256" ], query.values_at("client_id", "code_challenge_method")
    stub_sign_in

    get teams_sign_in_callback_path, params: { code: "c1", state: query["state"] }

    assert_redirected_to teams_approval_path(@token)
    assert_match(/Connected/, flash[:notice])
    assert @integration.reload.active?
    follow_redirect!
    assert_inertia_props { |props| props[:state] == "connected" && props[:organization] == "contoso.com" }
    get teams_approval_package_path(@token)
    assert_equal "application/zip", response.media_type
  end

  test "a sign-in without an administrator role is turned back with the reason" do
    get teams_approval_path(@token)
    state = sign_in_state
    stub_sign_in(wids: [])

    get teams_sign_in_callback_path, params: { code: "c1", state: state }

    assert_redirected_to teams_approval_path(@token)
    assert_match(/not an administrator/, flash[:alert])
    assert_equal "inactive", @integration.reload.status
  end

  test "a sign-in counts only in the browser that opened the approval link" do
    get teams_approval_path(@token)
    state = sign_in_state
    reset!
    stub_sign_in

    get teams_sign_in_callback_path, params: { code: "c1", state: state }

    assert_match(/Open the approval link again/, flash[:alert])
    assert_equal "inactive", @integration.reload.status
  end

  test "a sign-in cannot be replayed" do
    get teams_approval_path(@token)
    state = sign_in_state
    stub_sign_in
    get teams_sign_in_callback_path, params: { code: "c1", state: state }

    get teams_sign_in_callback_path, params: { code: "c1", state: state }

    assert_match(/already used/, flash[:alert])
  end

  test "the app is not handed out before the organization is connected" do
    get teams_approval_package_path(@token)

    assert_redirected_to teams_approval_path(@token)
  end

  test "file access is asked of the organization's own administrator and confirmed from Entra" do
    stub_sign_in
    Teams::Connection.complete!(integration: @integration, code: "c1", code_verifier: "v1")
    get teams_approval_path(@token)
    get teams_approval_file_access_path(@token)
    consent = URI.parse(response.location)
    assert_equal "/#{TEAMS_CUSTOMER_TENANT}/adminconsent", consent.path
    stub_request(:post, "https://login.microsoftonline.com/#{TEAMS_CUSTOMER_TENANT}/oauth2/v2.0/token")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { access_token: JWT.encode({ roles: [ "Files.ReadWrite.All" ] }, "k", "HS256"), expires_in: 3600 }.to_json)

    get teams_file_access_callback_path, params: { admin_consent: "True", tenant: TEAMS_CUSTOMER_TENANT,
                                                   state: Rack::Utils.parse_query(consent.query)["state"] }

    assert_redirected_to teams_approval_path(@token)
    assert_equal "File access granted", flash[:notice]
    assert @integration.reload.settings["file_access"]
  end

  test "a declined consent records nothing" do
    stub_sign_in
    Teams::Connection.complete!(integration: @integration, code: "c1", code_verifier: "v1")
    get teams_approval_path(@token)
    get teams_approval_file_access_path(@token)
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]

    get teams_file_access_callback_path, params: { error: "access_denied", state: state }

    assert_equal "File access was not granted", flash[:alert]
    assert_nil @integration.reload.settings["file_access"]
  end
end
