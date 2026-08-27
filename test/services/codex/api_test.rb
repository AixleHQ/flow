# frozen_string_literal: true

require "test_helper"

module Codex
  # Contract test for the Codex transport layer: the request it sends, the shape
  # it returns, and how each failure mode maps onto the error hierarchy.
  class ApiTest < ActiveSupport::TestCase
    # =========================================================================
    # models
    # =========================================================================

    test "models sends the bearer token and the client-version gate" do
      request = stub_request(:get, models_url)
        .with(headers: { "Authorization" => "Bearer tok", "Accept" => "application/json" })
        .to_return(models_response([ { "slug" => "gpt-5.6-sol", "visibility" => "list" } ]))

      Api.models(access_token: "tok")

      assert_requested request
    end

    test "models keeps a client version new enough for the current catalog" do
      # The endpoint hides models whose minimal_client_version is above the version
      # we claim — the gpt-5.6 family requires 0.144.0, which is why an older
      # client_version left those models out of the model picker entirely.
      assert_operator Gem::Version.new(Api::CLIENT_VERSION), :>=, Gem::Version.new("0.144.0"),
                      "Codex::Api::CLIENT_VERSION must be at least the gpt-5.6 minimal client version"
    end

    test "models returns the catalog including hidden and upgradable entries" do
      stub_request(:get, models_url).to_return(models_response([
        { "slug" => "gpt-5.6-sol", "display_name" => "GPT-5.6-Sol", "description" => "Fast", "visibility" => "list" },
        { "slug" => "gpt-5.4", "visibility" => "hide", "upgrade" => { "model" => "gpt-5.6-terra" } }
      ]))

      models = Api.models(access_token: "tok")

      listed, hidden = models
      assert_equal "gpt-5.6-sol", listed.slug
      assert_equal "GPT-5.6-Sol", listed.display_name
      assert_equal "Fast", listed.description
      assert listed.listed?
      refute_predicate listed, :upgradable?

      assert_equal "gpt-5.4", hidden.slug
      # A hidden model still has to reach the caller: a session pinned to an older
      # model is exactly the case whose upgrade target needs acknowledging.
      refute_predicate hidden, :listed?
      assert hidden.upgradable?
      assert_equal "gpt-5.6-terra", hidden.upgrade_target
    end

    test "models falls back to the slug when the catalog omits a display name" do
      stub_request(:get, models_url).to_return(models_response([ { "slug" => "gpt-5.4" } ]))

      model = Api.models(access_token: "tok").sole

      assert_equal "gpt-5.4", model.display_name
      assert_equal "", model.description
      assert_nil model.upgrade_target
    end

    test "models tolerates a catalog with no models key and skips non-object entries" do
      stub_request(:get, models_url).to_return(json_response({ "not_models" => 1 }))
      assert_empty Api.models(access_token: "tok")

      stub_request(:get, models_url).to_return(json_response({ "models" => [ "junk", nil ] }))
      assert_empty Api.models(access_token: "tok")
    end

    test "models raises UnauthorizedError on 401 so the caller can refresh the token" do
      stub_request(:get, models_url).to_return(status: 401, body: "expired")

      error = assert_raises(Api::UnauthorizedError) { Api.models(access_token: "stale") }

      assert_equal 401, error.status
      assert_equal "expired", error.body
      assert_match(/models failed: HTTP 401/, error.message)
    end

    test "models raises HTTPError on any other failure status" do
      stub_request(:get, models_url).to_return(status: 500, body: "boom")

      error = assert_raises(Api::HTTPError) { Api.models(access_token: "tok") }

      assert_equal 500, error.status
      refute_kind_of Api::UnauthorizedError, error
    end

    test "models raises ParseError on a body that is not a JSON object" do
      stub_request(:get, models_url).to_return(status: 200, body: "not json")
      assert_raises(Api::ParseError) { Api.models(access_token: "tok") }

      stub_request(:get, models_url).to_return(status: 200, body: "[]")
      assert_raises(Api::ParseError) { Api.models(access_token: "tok") }
    end

    test "models raises TimeoutError when the endpoint does not answer in time" do
      stub_request(:get, models_url).to_timeout

      assert_raises(Api::TimeoutError) { Api.models(access_token: "tok") }
    end

    test "models raises TransportError when the connection fails" do
      stub_request(:get, models_url).to_raise(Faraday::ConnectionFailed.new("no route"))

      assert_raises(Api::TransportError) { Api.models(access_token: "tok") }
    end

    # =========================================================================
    # usage
    # =========================================================================

    test "usage sends the bearer token and ChatGPT account id" do
      request = stub_request(:get, Api::USAGE_URL)
        .with(headers: { "Authorization" => "Bearer tok", "ChatGPT-Account-Id" => "acct-1" })
        .to_return(json_response({ "rate_limit" => {} }))

      assert_equal({ "rate_limit" => {} }, Api.usage(access_token: "tok", account_id: "acct-1"))
      assert_requested request
    end

    test "usage omits an absent account id and preserves HTTP failures" do
      request = stub_request(:get, Api::USAGE_URL)
        .with(headers: { "Authorization" => "Bearer tok" })
        .to_return(status: 429, body: "slow down")

      error = assert_raises(Api::HTTPError) { Api.usage(access_token: "tok") }
      assert_equal 429, error.status
      assert_requested request
    end

    # =========================================================================
    # refresh_tokens
    # =========================================================================

    test "refresh_tokens posts the OAuth grant and returns the rotated tokens" do
      request = stub_request(:post, Api::OAUTH_TOKEN_URL)
        .with(headers: { "Content-Type" => "application/x-www-form-urlencoded" },
              body: { grant_type: "refresh_token", client_id: Api::OAUTH_CLIENT_ID, refresh_token: "r1" })
        .to_return(json_response({ "access_token" => "a2", "refresh_token" => "r2", "id_token" => "id2" }))

      tokens = Api.refresh_tokens(refresh_token: "r1")

      assert_requested request
      assert_equal "a2", tokens.access_token
      assert_equal "r2", tokens.refresh_token
      assert_equal "id2", tokens.id_token
    end

    test "refresh_tokens leaves the omitted tokens nil for the caller to fill in" do
      # Deciding what to keep when the server rotates only the access token is the
      # caller's business — the transport reports exactly what came back.
      stub_request(:post, Api::OAUTH_TOKEN_URL).to_return(json_response({ "access_token" => "a2" }))

      tokens = Api.refresh_tokens(refresh_token: "r1")

      assert_equal "a2", tokens.access_token
      assert_nil tokens.refresh_token
      assert_nil tokens.id_token
    end

    test "refresh_tokens raises HTTPError when the grant is rejected" do
      stub_request(:post, Api::OAUTH_TOKEN_URL).to_return(status: 400, body: "invalid_grant")

      error = assert_raises(Api::HTTPError) { Api.refresh_tokens(refresh_token: "r1") }

      assert_equal 400, error.status
      assert_equal "invalid_grant", error.body
    end

    test "refresh_tokens raises UnauthorizedError when the refresh token itself is rejected" do
      stub_request(:post, Api::OAUTH_TOKEN_URL).to_return(status: 401, body: "")

      assert_raises(Api::UnauthorizedError) { Api.refresh_tokens(refresh_token: "r1") }
    end

    private

    def models_url
      "#{Api::MODELS_URL}?client_version=#{Api::CLIENT_VERSION}"
    end

    def models_response(models)
      json_response({ "models" => models })
    end

    def json_response(body)
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end
  end
end
