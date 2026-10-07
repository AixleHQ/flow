# frozen_string_literal: true

require "test_helper"

# A Slack sender linking their Slack account to their Aixle account with Sign in
# with Slack. Slack is the fake client; the signed OAuth state round-trips
# through a real cache.
class Web::Integrations::SlackLinkTest < ActionDispatch::IntegrationTest
  setup do
    Settings.stubs(:slack).returns(Hashie::Mash.new(client_id: "123.456", client_secret: "s3cret", signing_secret: "sig",
                                                    scopes: "chat:write,commands"))
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    stub_slack_client!
    @user = create(:user, :with_company, :onboarding_completed, name: "Ada Lovelace", password: AuthHelper::TEST_PASSWORD)
    @company = @user.companies.first
    @integration = Integration.create!(provider: :slack, company: @company, connected_by: @user, name: "Acme",
                                       status: :active, settings: { "team_id" => "T1" })
    @token = URI.parse(Slack::AccountLink.url_for(integration: @integration, team_id: "T1", user_id: "U1"))
                .path.split("/").last
  end

  def sign_in_with_slack_as(user_id:, team_id: "T1")
    get slack_link_path(@token)
    post slack_link_sign_in_path(@token)
    authorize = URI.parse(response.location)
    query = Rack::Utils.parse_query(authorize.query)
    assert_equal [ "slack.com", "/openid/connect/authorize" ], [ authorize.host, authorize.path ]
    assert_equal [ "T1", "#{Slack::Oauth.redirect_uri}/link" ], query.values_at("team", "redirect_uri")
    fake_slack.openid_claims = { "aud" => "123.456", "exp" => 1.hour.from_now.to_i, "nonce" => query["nonce"],
                                 "https://slack.com/team_id" => team_id, "https://slack.com/user_id" => user_id }
    get slack_link_callback_path, params: { code: "c1", state: query["state"] }
  end

  test "Sign in with Slack as the sender links their Slack account to the Aixle account signed in" do
    sign_in_as(@user)

    sign_in_with_slack_as(user_id: "U1")

    assert_redirected_to slack_link_path(@token)
    assert_equal @user, Slack::Sender.user("T1", "U1")
    assert_equal "#{Slack::Oauth.redirect_uri}/link", fake_slack.openid_exchanges.sole[:redirect_uri]
    get slack_link_path(@token)
    assert_inertia_page "Integrations/ChatLink"
    assert_inertia_props { |props| props[:state] == "linked" && props[:messenger] == "Slack" }
  end

  test "a sign-in as anyone but the sender links nothing" do
    sign_in_as(@user)

    sign_in_with_slack_as(user_id: "U2")

    assert_nil Slack::Sender.user("T1", "U1")
    assert_match(/not the one that asked/, flash[:alert])
  end

  test "an account that may no longer sign in is nobody" do
    ChatIdentity.create!(provider: "slack", workspace_id: "T1", external_user_id: "U1", user: @user,
                         proof: "slack_sign_in", linked_at: Time.current)

    @user.soft_delete!

    assert_nil Slack::Sender.user("T1", "U1")
  end
end
