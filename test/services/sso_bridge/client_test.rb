# frozen_string_literal: true

require "test_helper"

module SsoBridge
  # Contract test for the SAML bridge's admin API: realistic payloads over
  # WebMock, so the wire format is pinned in one place instead of being guessed
  # at from feature tests.
  class ClientTest < ActiveSupport::TestCase
    ADMIN = "https://sso-bridge.internal"

    setup do
      @client = SsoBridge::Client.new(admin_url: ADMIN, api_key: "test-api-key")
    end

    test "a connection is created from a metadata URL, authenticated with the API key" do
      stub_request(:post, "#{ADMIN}/api/v1/sso")
             .with(headers: { "Authorization" => "Api-Key test-api-key" })
             .to_return(status: 201, headers: { "Content-Type" => "application/json" },
                        body: { clientID: "bridge-client-id", clientSecret: "bridge-secret",
                                tenant: "company-1", product: "aixle" }.to_json)

      result = @client.upsert_connection(
        tenant: "company-1", product: "aixle", name: "Acme SAML",
        metadata_url: "https://idp.acme.test/metadata",
        redirect_url: "https://app.test", default_redirect_url: "https://app.test/auth/oidc/callback"
      )

      assert_equal "bridge-client-id", result["clientID"]
      assert_requested :post, "#{ADMIN}/api/v1/sso" do |req|
        body = Rack::Utils.parse_query(req.body)
        # The redirect allowlist is a security control on the bridge side, so it
        # has to actually arrive.
        body["metadataUrl"] == "https://idp.acme.test/metadata" &&
          body["redirectUrl"] == [ "https://app.test" ].to_json &&
          body["tenant"] == "company-1"
      end
    end

    test "raw metadata is sent base64-encoded" do
      stub_request(:post, "#{ADMIN}/api/v1/sso").to_return(
        status: 201, headers: { "Content-Type" => "application/json" }, body: "{}"
      )

      @client.upsert_connection(
        tenant: "company-1", product: "aixle", name: "Acme SAML",
        raw_metadata: "<EntityDescriptor/>",
        redirect_url: "https://app.test", default_redirect_url: "https://app.test/cb"
      )

      assert_requested :post, "#{ADMIN}/api/v1/sso" do |req|
        Rack::Utils.parse_query(req.body)["encodedRawMetadata"] ==
          Base64.strict_encode64("<EntityDescriptor/>")
      end
    end

    test "a connection with neither metadata form is refused before any request" do
      assert_raises(SsoBridge::Client::Error) do
        @client.upsert_connection(tenant: "t", product: "p", name: "n",
                                  redirect_url: "https://app.test", default_redirect_url: "https://app.test/cb")
      end
      assert_not_requested :post, "#{ADMIN}/api/v1/sso"
    end

    test "a bridge error is raised, never swallowed into a half-made connection" do
      stub_request(:post, "#{ADMIN}/api/v1/sso").to_return(status: 400, body: "bad metadata")

      assert_raises(SsoBridge::Client::Error) do
        @client.upsert_connection(tenant: "t", product: "p", name: "n",
                                  metadata_url: "https://idp.test/m",
                                  redirect_url: "https://app.test", default_redirect_url: "https://app.test/cb")
      end
    end

    test "deleting a connection names the tenant and product" do
      stub_request(:delete, "#{ADMIN}/api/v1/sso")
        .with(query: { tenant: "company-1", product: "aixle" })
        .to_return(status: 200, body: "")

      assert @client.delete_connection(tenant: "company-1", product: "aixle")
    end

    test "an installation with no bridge configured refuses to build a client" do
      assert_raises(SsoBridge::Client::NotConfigured) do
        SsoBridge::Client.new(admin_url: "", api_key: "")
      end
    end
  end
end
