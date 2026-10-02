# frozen_string_literal: true

require "test_helper"

class Linear::OauthTest < ActiveSupport::TestCase
  setup { with_linear_oauth_app }

  test "the authorize URL installs the app as itself, with a signed single-use state" do
    company = create(:company)
    project = create(:project, company: company, owner: create(:user, company: company))
    uri = URI.parse(Linear::Oauth.authorize_url(project: project, user: project.owner))
    query = URI.decode_www_form(uri.query).to_h

    assert_equal "https://linear.app/oauth/authorize", "#{uri.scheme}://#{uri.host}#{uri.path}"
    assert_equal [ "linear-app-client", "app", "read,write", "code" ], query.values_at("client_id", "actor", "scope", "response_type")
    assert_equal({ "provider" => "linear", "owner_id" => project.id }, Oauth::State.decode(query["state"]).slice("provider", "owner_id"))
  end

  test "the code is exchanged form-encoded for a token that expires" do
    stub_request(:post, "https://api.linear.app/oauth/token")
      .with(body: hash_including("grant_type" => "authorization_code", "code" => "c0de", "client_secret" => "linear-app-secret"),
            headers: { "Content-Type" => "application/x-www-form-urlencoded" })
      .to_return(status: 200, body: { access_token: "t", refresh_token: "r", expires_in: 86_399 }.to_json)

    freeze_time do
      assert_equal({ "access_token" => "t", "refresh_token" => "r", "expires_at" => 86_399.seconds.from_now.iso8601 },
                   Linear::Oauth.exchange_code("c0de"))
    end
  end
end
