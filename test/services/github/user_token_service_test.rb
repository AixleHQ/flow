# frozen_string_literal: true

require "test_helper"

module Github
  # Contract tests (testing doctrine R4): the adapter is pinned to the api.github.com
  # surface with WebMock. The same payload shapes pin FakeGithub::UserTokenService.
  class UserTokenServiceTest < ActiveSupport::TestCase
    SCOPED_URL = "https://api.github.com/applications/Iv1.client/token/scoped"
    GRANT_URL = "https://api.github.com/applications/Iv1.client/grant"
    JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

    setup do
      Settings.github.stubs(:client_id).returns("Iv1.client")
      Settings.github.stubs(:client_secret).returns("client-secret")
      @service = UserTokenService.new
    end

    test "scoped_token posts the target, repositories and permissions with the App's client credentials" do
      stub = stub_request(:post, SCOPED_URL)
             .with(basic_auth: [ "Iv1.client", "client-secret" ]) { |req|
               JSON.parse(req.body).values_at("access_token", "target", "repositories", "permissions") ==
                 [ "ghu_user", "acme", [ "flow" ], { "contents" => "write" } ]
             }
             .to_return(status: 201, headers: JSON_HEADERS,
                        body: { token: "ghu_scoped", expires_at: "2026-11-12T04:00:00Z", token_last_eight: "_scoped_" }.to_json)

      result = @service.scoped_token(user_token: "ghu_user", target: "acme", repositories: [ "flow" ],
                                     permissions: { "contents" => "write" })

      assert_requested stub
      assert_equal "ghu_scoped", result[:token]
      assert_equal Time.zone.parse("2026-11-12T04:00:00Z"), result[:expires_at]
      assert_equal "_scoped_", result[:token_last_eight]
    end

    test "scoped_token maps 404 to InvalidToken, 403 and 422 to Forbidden, 5xx to Unavailable" do
      { 404 => UserTokenService::InvalidToken, 403 => UserTokenService::Forbidden,
        422 => UserTokenService::Forbidden, 502 => UserTokenService::Unavailable }.each do |status, error|
        stub_request(:post, SCOPED_URL).to_return(status: status, headers: JSON_HEADERS, body: { message: "ghu_leaky" }.to_json)

        raised = assert_raises(error) do
          @service.scoped_token(user_token: "ghu_user", target: "acme", repositories: [ "flow" ], permissions: {})
        end
        assert_not_includes raised.message, "ghu_leaky"
      end
    end

    test "user reads the profile of the token's owner" do
      stub_request(:get, "https://api.github.com/user").with(headers: { "Authorization" => "token ghu_user" })
        .to_return(status: 200, headers: JSON_HEADERS,
                   body: { id: 7, login: "octo", name: nil, avatar_url: "https://a.test/7" }.to_json)

      assert_equal({ id: 7, login: "octo", name: nil, avatar_url: "https://a.test/7" }, @service.user("ghu_user"))
    end

    test "revoke_grant deletes the App's grant for the user token" do
      stub = stub_request(:delete, GRANT_URL).with { |req| JSON.parse(req.body)["access_token"] == "ghu_user" }
                                             .to_return(status: 204)

      assert @service.revoke_grant("ghu_user")
      assert_requested stub
    end
  end
end
