# frozen_string_literal: true

require "test_helper"

# Unit test for Oauth::Providers — the static provider registry that reconciles a
# `source: "static"` OauthClient row from Settings-backed client credentials.
#
# Depends on Builder A's OauthClient model + the `oauth_key`/`sentry_oauth`/
# `railway_oauth` Settings keys; the provider Settings are stubbed so the test does
# not require live operator credentials.
class Oauth::ProvidersTest < ActiveSupport::TestCase
  test "known? / config / provider_names cover the Phase-1 providers" do
    assert Oauth::Providers.known?("sentry")
    assert Oauth::Providers.known?("railway")
    refute Oauth::Providers.known?("github")
    refute Oauth::Providers.known?(nil)

    assert_equal %w[sentry railway].sort, Oauth::Providers.provider_names.sort
    assert_equal "https://sentry.io", Oauth::Providers.config("sentry")[:issuer]
  end

  test "config raises KeyError for an unknown provider" do
    assert_raises(KeyError) { Oauth::Providers.config("nope") }
  end

  test "client_for raises MissingClientConfig when Settings has no client_id" do
    Settings.stubs(:sentry_oauth).returns(nil)
    error = assert_raises(Oauth::MissingClientConfig) { Oauth::Providers.client_for("sentry") }
    assert_equal "sentry", error.message
  end

  test "client_for raises MissingClientConfig when client_id is blank" do
    Settings.stubs(:sentry_oauth).returns(OpenStruct.new(client_id: "", client_secret: "x"))
    assert_raises(Oauth::MissingClientConfig) { Oauth::Providers.client_for("sentry") }
  end

  test "client_for reconciles a confidential static OauthClient from Settings" do
    Settings.stubs(:sentry_oauth).returns(
      OpenStruct.new(client_id: "sentry-cid", client_secret: "sentry-secret")
    )

    client = nil
    assert_difference("OauthClient.count", 1) do
      client = Oauth::Providers.client_for("sentry")
    end

    assert_equal "https://sentry.io", client.issuer
    assert_equal "https://sentry.io/oauth/authorize/", client.authorization_endpoint
    assert_equal "https://sentry.io/oauth/token/", client.token_endpoint
    assert_equal "org:read project:read event:read", client.scopes
    assert_equal "static", client.source
    assert_equal "sentry-cid", client.client_id
    assert_equal "sentry-secret", client.client_secret
    assert client.confidential?, "a client with a secret is confidential"
  end

  test "client_for is idempotent: the same (issuer, client_id) reconciles one row" do
    Settings.stubs(:sentry_oauth).returns(
      OpenStruct.new(client_id: "sentry-cid", client_secret: "sentry-secret")
    )

    first = Oauth::Providers.client_for("sentry")
    assert_no_difference("OauthClient.count") do
      second = Oauth::Providers.client_for("sentry")
      assert_equal first.id, second.id
    end
  end

  test "client_for builds a public (PKCE-only) client when no secret is configured" do
    Settings.stubs(:railway_oauth).returns(OpenStruct.new(client_id: "railway-cid"))

    client = Oauth::Providers.client_for("railway")
    assert_equal "railway-cid", client.client_id
    assert_nil client.client_secret
    refute_predicate client, :confidential?, "a client without a secret is public (PKCE-only)"
  end
end
