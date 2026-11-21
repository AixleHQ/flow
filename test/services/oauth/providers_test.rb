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
    assert Oauth::Providers.known?("github")
    assert Oauth::Providers.known?("gitlab")
    assert Oauth::Providers.known?("bitbucket")
    refute Oauth::Providers.known?(nil)

    assert_equal %w[sentry railway github gitlab bitbucket].sort, Oauth::Providers.provider_names.sort
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

  test "the gitlab entry takes its endpoints and issuer from GITLAB_ENDPOINT" do
    Settings.gitlab.stubs(:endpoint).returns("https://git.example.com/api/v4")

    config = Oauth::Providers.config("gitlab")

    assert_equal "https://git.example.com", config[:issuer]
    assert_equal "https://git.example.com/oauth/authorize", config[:authorization_endpoint]
    assert_equal "https://git.example.com/oauth/token", config[:token_endpoint]
    assert_equal "api", config[:scopes]
    assert_equal %w[User], config[:owner_types]
  end

  test "client_for reads the GitLab OAuth app's own setting names" do
    Settings.gitlab.stubs(:endpoint).returns("https://git.example.com/api/v4")
    Settings.gitlab.stubs(:oauth_client_id).returns("lab-cid")
    Settings.gitlab.stubs(:oauth_client_secret).returns("lab-secret")

    client = Oauth::Providers.client_for("gitlab")

    assert_equal "https://git.example.com", client.issuer
    assert_equal "lab-cid", client.client_id
    assert_equal "lab-secret", client.client_secret
    assert_equal "api", client.scopes
  end

  test "client_for raises MissingClientConfig when the GitLab OAuth app is not set" do
    Settings.gitlab.stubs(:oauth_client_id).returns("")

    assert_raises(Oauth::MissingClientConfig) { Oauth::Providers.client_for("gitlab") }
  end

  test "only gitlab trusts the operator's host for the token call" do
    Settings.gitlab.stubs(:endpoint).returns("https://git.example.com/api/v4")

    assert_equal [ "git.example.com" ], Oauth::Providers.trusted_hosts("gitlab")
    assert_empty Oauth::Providers.trusted_hosts("github")
    assert_empty Oauth::Providers.trusted_hosts("mcp:abc")
    assert_empty Oauth::Providers.trusted_hosts(nil)
  end

  test "the bitbucket entry has fixed Cloud endpoints, no scope and Basic client authentication" do
    config = Oauth::Providers.config("bitbucket")

    assert_equal "https://bitbucket.org", config[:issuer]
    assert_equal "https://bitbucket.org/site/oauth2/authorize", config[:authorization_endpoint]
    assert_equal "https://bitbucket.org/site/oauth2/access_token", config[:token_endpoint]
    assert_equal "", config[:scopes]
    assert_equal %w[User], config[:owner_types]
    assert_nil config[:revocation_endpoint]
    assert_empty Oauth::Providers.trusted_hosts("bitbucket")
  end

  test "client_auth is basic for bitbucket and post for every other provider" do
    assert_equal :basic, Oauth::Providers.client_auth("bitbucket")
    %w[sentry railway github gitlab mcp:example.com].each do |provider|
      assert_equal :post, Oauth::Providers.client_auth(provider), provider
    end
  end

  test "client_for reads the Bitbucket OAuth client's settings" do
    Settings.bitbucket.oauth.stubs(:client_id).returns("bb-cid")
    Settings.bitbucket.oauth.stubs(:client_secret).returns("bb-secret")

    client = Oauth::Providers.client_for("bitbucket")

    assert_equal "https://bitbucket.org", client.issuer
    assert_equal "bb-cid", client.client_id
    assert_equal "bb-secret", client.client_secret
    assert_equal "", client.scopes.to_s
  end

  test "client_for raises MissingClientConfig when the Bitbucket OAuth client is not set" do
    Settings.bitbucket.oauth.stubs(:client_id).returns("")

    assert_raises(Oauth::MissingClientConfig) { Oauth::Providers.client_for("bitbucket") }
  end
end
