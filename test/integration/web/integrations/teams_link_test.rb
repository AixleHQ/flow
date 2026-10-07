# frozen_string_literal: true

require "test_helper"

# A Teams sender linking their Teams account to their Aixle account. Entra is
# WebMock-stubbed; the signed OAuth state round-trips through a real cache.
class Web::Integrations::TeamsLinkTest < ActionDispatch::IntegrationTest
  SENDER = "b130c271-0000-4000-8000-000000000001"

  setup do
    with_teams_enabled
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @user = create(:user, :with_company, :onboarding_completed, name: "Ada Lovelace", password: AuthHelper::TEST_PASSWORD)
    @company = @user.companies.first
    @integration = Integration.create!(provider: :teams, company: @company, connected_by: @user, name: "Contoso",
                                       status: :active, settings: { "tenant_id" => TEAMS_CUSTOMER_TENANT })
    @token = URI.parse(Teams::AccountLink.url_for(integration: @integration, tenant_id: TEAMS_CUSTOMER_TENANT,
                                                  object_id: SENDER)).path.split("/").last
  end

  def stub_tenant_sign_in(oid: SENDER, tid: TEAMS_CUSTOMER_TENANT)
    claims = { aud: TEAMS_APP_ID, tid: tid, oid: oid, name: "Ada", exp: 1.hour.from_now.to_i }
    stub_request(:post, "https://login.microsoftonline.com/#{TEAMS_CUSTOMER_TENANT}/oauth2/v2.0/token")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id_token: JWT.encode(claims, "test", "HS256") }.to_json)
  end

  def sign_in_and_come_back(oid: SENDER)
    get teams_link_path(@token)
    post teams_link_sign_in_path(@token)
    authorize = URI.parse(response.location)
    assert_equal "/#{TEAMS_CUSTOMER_TENANT}/oauth2/v2.0/authorize", authorize.path
    stub_tenant_sign_in(oid: oid)
    get teams_sign_in_callback_path, params: { code: "c1", state: Rack::Utils.parse_query(authorize.query)["state"] }
    follow_redirect!
  end

  test "a visitor who is not signed in is asked to sign in to Aixle first" do
    get teams_link_path(@token)

    assert_inertia_page "Integrations/TeamsLink"
    assert_inertia_props { |props| props[:state] == "sign_in" }
  end

  test "a Microsoft sign-in as the sender links their Teams account to the Aixle account signed in" do
    sign_in_as(@user)

    sign_in_and_come_back

    assert_redirected_to teams_link_path(@token)
    assert_equal @user.id, Teams::Sender.user_id(TEAMS_CUSTOMER_TENANT, SENDER)
    get teams_link_path(@token)
    assert_inertia_props { |props| props[:state] == "linked" }
  end

  test "a sign-in as anyone but the sender links nothing" do
    sign_in_as(@user)

    sign_in_and_come_back(oid: "someone-else")

    assert_nil Teams::Sender.user_id(TEAMS_CUSTOMER_TENANT, SENDER)
    assert_match(/not the Teams account that asked/, flash[:alert])
  end

  test "a forged or expired link is refused" do
    sign_in_as(@user)

    get teams_link_path("#{@token}x")
    assert_inertia_props { |props| props[:state] == "expired" }

    travel 2.hours do
      get teams_link_path(@token)
      assert_inertia_props { |props| props[:state] == "expired" }
    end
  end

  test "an Aixle account of another company cannot link a sender of this organization" do
    outsider = create(:user, :with_company, :onboarding_completed, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(outsider)

    get teams_link_path(@token)

    assert_inertia_props { |props| props[:state] == "other_company" && props[:workspace] == @company.name }
  end
end
