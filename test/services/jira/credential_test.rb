# frozen_string_literal: true

require "test_helper"

class Jira::CredentialTest < ActiveSupport::TestCase
  setup do
    with_jira_oauth_app
    freeze_time
  end

  def token_endpoint(body)
    stub_request(:post, "#{JIRA_AUTH}/oauth/token").with(body: hash_including(body))
  end

  test "a token that is still fresh is used as it is" do
    integration = create(:integration, :jira_oauth, :active)

    assert_equal({ "Authorization" => "Bearer jira-token" }, Jira::Credential.new(integration).authorization_headers)
  end

  test "an expiring 3LO token is refreshed and the rotated refresh token stored" do
    integration = create(:integration, :jira_oauth, :active)
    integration.update!(credentials_data: integration.credentials_data.merge("expires_at" => 2.minutes.from_now.iso8601))
    token_endpoint("grant_type" => "refresh_token", "refresh_token" => "jira-refresh")
      .to_return(status: 200, body: { access_token: "at-2", refresh_token: "rt-2", expires_in: 3600 }.to_json)

    assert_equal "at-2", Jira::Credential.new(integration).access_token
    assert_equal [ "at-2", "rt-2" ], integration.reload.credentials_data.values_at("access_token", "refresh_token")
  end

  test "a service account asks for a new client-credentials token" do
    integration = create(:integration, :jira, :active)
    integration.update!(credentials_data: integration.credentials_data.merge("expires_at" => 1.minute.ago.iso8601))
    token_endpoint("grant_type" => "client_credentials", "client_id" => "sa-client")
      .to_return(status: 200, body: { access_token: "sa-2", expires_in: 3600 }.to_json)

    assert_equal "sa-2", Jira::Credential.new(integration).access_token
    assert_equal [ "sa-2", "sa-secret" ], integration.reload.credentials_data.values_at("access_token", "client_secret")
  end

  test "a refused token is renewed once, unless another process already renewed it" do
    integration = create(:integration, :jira_oauth, :active)
    credential = Jira::Credential.new(integration)
    credential.access_token
    Integration.find(integration.id).update!(credentials_data: integration.credentials_data.merge("access_token" => "someone-elses"))

    assert_equal "someone-elses", credential.invalidate!
    assert_not_requested :post, "#{JIRA_AUTH}/oauth/token"
  end

  test "a grant Atlassian refuses puts the connection in error, asking for a reconnect" do
    integration = create(:integration, :jira_oauth, :active)
    integration.update!(credentials_data: integration.credentials_data.merge("expires_at" => 1.minute.ago.iso8601))
    token_endpoint("grant_type" => "refresh_token").to_return(status: 403, body: { error: "invalid_grant" }.to_json)

    error = assert_raises(Jira::Error) { Jira::Credential.new(integration).access_token }

    assert_equal "not_authorized", error.code
    integration.reload
    assert_equal [ "error", Jira::Credential::REAUTHORIZE ], [ integration.status, integration.settings["error"] ]
    assert_equal "jira-refresh", integration.credentials_data["refresh_token"]
  end
end
