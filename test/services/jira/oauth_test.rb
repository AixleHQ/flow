# frozen_string_literal: true

require "test_helper"

class Jira::OauthTest < ActiveSupport::TestCase
  setup { with_jira_oauth_app }

  test "the authorize URL asks Atlassian for consent to the Jira scopes, with a signed single-use state" do
    project = create(:integration, :jira).project
    user = project.owner

    uri = URI.parse(Jira::Oauth.authorize_url(project: project, user: user))
    query = Rack::Utils.parse_query(uri.query)

    assert_equal "https://auth.atlassian.com/authorize", "#{uri.scheme}://#{uri.host}#{uri.path}"
    assert_equal [ "api.atlassian.com", "jira-app-client", "code", "consent" ],
                 query.values_at("audience", "client_id", "response_type", "prompt")
    assert_includes query["scope"].split, "offline_access"
    assert_includes query["scope"].split, "read:board-scope.admin:jira-software"
    state = Oauth::State.decode(query["state"])
    assert_equal [ "jira", project.id, user.id ], state.values_at("provider", "owner_id", "user_id")
  end

  test "exchanging a code keeps the rotated refresh token and when the access token expires" do
    freeze_time
    stub_request(:post, "#{JIRA_AUTH}/oauth/token")
      .with(body: hash_including("grant_type" => "authorization_code", "code" => "abc", "client_secret" => "jira-app-secret"))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { access_token: "at-1", refresh_token: "rt-1", expires_in: 3600, scope: "read:jira-work" }.to_json)

    token = Jira::Oauth.exchange_code("abc")

    assert_equal({ "access_token" => "at-1", "refresh_token" => "rt-1", "expires_at" => 1.hour.from_now.iso8601 }, token)
  end

  test "a refused grant is not_authorized, with Atlassian's reason" do
    stub_request(:post, "#{JIRA_AUTH}/oauth/token")
      .to_return(status: 403, body: { error: "invalid_grant", error_description: "Unknown or invalid refresh token." }.to_json)

    error = assert_raises(Jira::Error) { Jira::Oauth.refresh("rt-old") }

    assert_equal "not_authorized", error.code
    assert_match(/invalid refresh token/, error.message)
  end

  test "a service account's token comes from the client-credentials grant" do
    stub_request(:post, "#{JIRA_AUTH}/oauth/token")
      .with(body: { grant_type: "client_credentials", client_id: "sa-client", client_secret: "sa-secret" }.to_json)
      .to_return(status: 200, body: { access_token: "sa-at", expires_in: 3600, token_type: "Bearer" }.to_json)

    assert_equal "sa-at", Jira::Oauth.client_credentials(client_id: "sa-client", client_secret: "sa-secret")["access_token"]
  end

  test "accessible resources lists the Jira sites once, leaving out other products" do
    stub_request(:get, "#{JIRA_API}/oauth/token/accessible-resources")
      .with(headers: { "Authorization" => "Bearer at-1" })
      .to_return(status: 200, body: [
        { id: "cloud-1", name: "acme", url: "https://acme.atlassian.net", scopes: [ "read:jira-work", "write:jira-work" ] },
        { id: "cloud-1", name: "acme", url: "https://acme.atlassian.net", scopes: [ "read:confluence-content.all" ] },
        { id: "cloud-2", name: "beta", url: "https://beta.atlassian.net", scopes: [ "read:jira-user" ] }
      ].to_json)

    assert_equal [ { id: "cloud-1", name: "acme", url: "https://acme.atlassian.net" },
                   { id: "cloud-2", name: "beta", url: "https://beta.atlassian.net" } ],
                 Jira::Oauth.accessible_resources("at-1")
  end

  test "a site's cloud id comes from its tenant endpoint, and only Atlassian site hosts are asked" do
    stub_request(:get, "https://acme.atlassian.net/_edge/tenant_info").to_return(status: 200, body: { cloudId: "cloud-1" }.to_json)

    assert_equal "cloud-1", Jira::Oauth.cloud_id_for("https://acme.atlassian.net/jira/software/projects")
    assert_equal "cloud-1", Jira::Oauth.cloud_id_for("acme.atlassian.net")
    %w[https://evil.example.com http://169.254.169.254 acme.atlassian.net.evil.com].each do |site|
      assert_equal "validation_failed", assert_raises(Jira::Error) { Jira::Oauth.cloud_id_for(site) }.code, site
    end
  end
end
