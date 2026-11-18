# frozen_string_literal: true

require "test_helper"

# Contract test of a client identified by a metadata document URL (CIMD), with
# the document Claude Code actually publishes.
class MCPAuth::ClientMetadataDocumentTest < ActiveSupport::TestCase
  URL = "https://claude.ai/oauth/claude-code-client-metadata"
  CLAUDE_CODE = {
    client_id: URL, client_name: "Claude Code", client_uri: "https://claude.ai",
    redirect_uris: %w[http://localhost/callback http://127.0.0.1/callback],
    grant_types: %w[authorization_code refresh_token], response_types: %w[code], token_endpoint_auth_method: "none"
  }.freeze

  setup { resolve_hosts_publicly! }

  def serve(body, status: 200)
    stub_request(:get, URL).to_return(status: status, body: body.is_a?(String) ? body : body.to_json,
                                      headers: { "Content-Type" => "application/json" })
  end

  test "reads the client's name and redirect URIs, and names it by the host it is served from" do
    serve(CLAUDE_CODE)

    client = MCPAuth::Client.resolve(URL)

    assert_equal "cimd", client.kind
    assert_equal "claude.ai", client.host
    assert_equal "Claude Code (claude.ai)", client.label
    assert_equal %w[http://localhost/callback http://127.0.0.1/callback], client.redirect_uris
  end

  test "refuses a document that names another client" do
    serve(CLAUDE_CODE.merge(client_id: "https://claude.ai/oauth/other"))

    error = assert_raises(MCPAuth::InvalidClient) { MCPAuth::Client.resolve(URL) }
    assert_match(/names a different client/, error.message)
  end

  test "refuses a document without redirect URIs, one that is not JSON, and one that is not there" do
    serve(CLAUDE_CODE.except(:redirect_uris))
    assert_raises(MCPAuth::InvalidClient) { MCPAuth::Client.resolve(URL) }

    serve("<html>")
    assert_raises(MCPAuth::InvalidClient) { MCPAuth::Client.resolve(URL) }

    serve("", status: 404)
    assert_raises(MCPAuth::InvalidClient) { MCPAuth::Client.resolve(URL) }
  end

  test "refuses a document larger than any client needs" do
    serve(CLAUDE_CODE.merge(padding: "x" * 20.kilobytes))

    error = assert_raises(MCPAuth::InvalidClient) { MCPAuth::Client.resolve(URL) }
    assert_match(/too large/, error.message)
  end

  test "does not fetch from an internal address" do
    UrlSafetyValidator.stubs(:resolved_addresses).returns([ IPAddr.new("10.0.0.5") ])

    error = assert_raises(MCPAuth::InvalidClient) { MCPAuth::Client.resolve(URL) }
    assert_match(/does not connect to/, error.message)
  end

  test "refuses a client ID that is not a document URL" do
    assert_raises(MCPAuth::InvalidClient) { MCPAuth::Client.resolve("https://claude.ai/") }
    assert_raises(MCPAuth::InvalidClient) { MCPAuth::Client.resolve("https://claude.ai/a#b") }
    assert_raises(MCPAuth::InvalidClient) { MCPAuth::Client.resolve("aocl_unknown") }
  end
end
