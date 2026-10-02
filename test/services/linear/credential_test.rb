# frozen_string_literal: true

require "test_helper"

class Linear::CredentialTest < ActiveSupport::TestCase
  TOKEN = "https://api.linear.app/oauth/token"

  setup { with_linear_oauth_app }

  test "an API key is the header as it is and cannot be renewed" do
    integration = create(:integration, :linear, :active)
    credential = Linear::Credential.new(integration)

    assert_equal({ "Authorization" => integration.credentials_data["api_key"] }, credential.authorization_headers)
    assert_equal "not_authorized", assert_raises(Trackers::Error) { credential.invalidate! }.code
  end

  test "an expired OAuth token is refreshed once and the rotated refresh token is stored" do
    integration = create(:integration, :linear_oauth, :active)
    integration.credentials_data = integration.credentials_data.merge("expires_at" => 1.minute.from_now.iso8601)
    integration.save!
    refresh = stub_request(:post, TOKEN).with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "lin_refresh"))
                                        .to_return(status: 200, body: { access_token: "new-token", refresh_token: "rotated", expires_in: 86_399 }.to_json)

    assert_equal({ "Authorization" => "Bearer new-token" }, Linear::Credential.new(integration).authorization_headers)
    assert_equal({ "Authorization" => "Bearer new-token" }, Linear::Credential.new(integration.reload).authorization_headers)
    assert_requested refresh, times: 1
    assert_equal "rotated", integration.reload.credentials_data["refresh_token"]
  end

  test "a refused refresh puts the connection in error and asks for a reconnect" do
    integration = create(:integration, :linear_oauth, :active)
    stub_request(:post, TOKEN).to_return(status: 400, body: { error: "invalid_grant" }.to_json)

    credential = Linear::Credential.new(integration)
    credential.authorization_headers

    assert_equal "not_authorized", assert_raises(Trackers::Error) { credential.invalidate! }.code
    assert_equal [ "error", Linear::Credential::REAUTHORIZE ], [ integration.reload.status.to_s, integration.settings["error"] ]
  end
end
