# frozen_string_literal: true

require "test_helper"

class OauthMailerTest < ActionMailer::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @client = OauthClient.create!(
      issuer: "https://sentry.io", authorization_endpoint: "https://sentry.io/a",
      token_endpoint: "https://sentry.io/t", client_id: "c1", source: "static"
    )
  end

  test "refresh_failed emails the owner with a reconnect link for an MCP credential" do
    server = create(:mcp_server, :custom, scope: @project, transport: :sse, auth_type: :oauth)
    cred = OauthCredential.create!(owner: @user, oauth_client: @client, mcp_server: server,
                                   provider: "mcp:sentry", status: :error, access_token: "t")

    mail = OauthMailer.refresh_failed(cred)

    assert_equal [ @user.email ], mail.to
    assert_match(/reconnect/i, mail.subject)
    assert_match "/oauth/mcp/#{server.id}/connect", mail.body.encoded
    assert_match "mcp:sentry", mail.body.encoded
  end

  test "refresh_failed for a direct-provider credential omits the MCP connect link" do
    cred = OauthCredential.create!(owner: @user, oauth_client: @client, provider: "sentry",
                                   status: :error, access_token: "t")

    mail = OauthMailer.refresh_failed(cred)

    assert_equal [ @user.email ], mail.to
    assert_no_match(/oauth\/mcp/, mail.body.encoded)
  end
end
