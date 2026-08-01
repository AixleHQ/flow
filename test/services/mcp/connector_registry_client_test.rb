# frozen_string_literal: true

require "test_helper"

module MCP
  # Contract tests for the registry HTTP boundary (testing doctrine R4: HTTP
  # adapters get WebMock stub_request contract tests with realistic payloads).
  #
  # Payloads come from the same captured fixtures the normalizer is tested
  # against, so "realistic" means literally what the registry served, not a
  # hand-written approximation that can drift into wishful thinking.
  class ConnectorRegistryClientTest < ActiveSupport::TestCase
    BASE = "https://registry.modelcontextprotocol.io"
    SERVERS_URL = "#{BASE}/v0.1/servers"

    def fixture_entry(name)
      JSON.parse(file_fixture("mcp_registry/#{name}.json").read)
    end

    def list_body(entries, next_cursor: nil)
      { "servers" => entries, "metadata" => { "count" => entries.size, "nextCursor" => next_cursor }.compact }.to_json
    end

    def stub_json(url, body, query: nil)
      stub = stub_request(:get, url)
      stub = stub.with(query: query) if query
      stub.to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
    end

    # -------------------------------------------------------------------- fetch

    test "fetches a single version and returns it normalized" do
      stub_json("#{SERVERS_URL}/app.linear%2Flinear/versions/latest", fixture_entry("single_version_response").to_json)

      manifest = ConnectorRegistryClient.fetch("app.linear/linear")

      assert_equal "app.linear/linear", manifest["name"]
      assert_equal "https://mcp.linear.app/mcp", manifest["targets"].first["url"]
    end

    test "url-encodes the slash in a server name rather than splitting the path" do
      stub_json("#{SERVERS_URL}/io.github.Evozim%2Flinear-broker/versions/1.0.0", fixture_entry("remote_secret_header").to_json)

      assert_equal "Linear-Task-Broker", ConnectorRegistryClient.fetch("io.github.Evozim/linear-broker", version: "1.0.0")["title"]
    end

    test "returns nil instead of raising when the registry is unavailable" do
      stub_request(:get, %r{#{SERVERS_URL}/.*}).to_return(status: 503)

      assert_nil ConnectorRegistryClient.fetch("app.linear/linear")
    end

    test "returns nil instead of raising when the registry times out" do
      stub_request(:get, %r{#{SERVERS_URL}/.*}).to_timeout

      assert_nil ConnectorRegistryClient.fetch("app.linear/linear")
    end

    test "returns nil for a blank name without calling out" do
      assert_nil ConnectorRegistryClient.fetch("")
      assert_not_requested :get, %r{#{BASE}}
    end

    # ------------------------------------------------------------------- search

    test "searches by name and normalizes every result" do
      stub_json(SERVERS_URL, list_body([ fixture_entry("remote_dual_transport"), fixture_entry("remote_secret_header") ]),
                query: { "search" => "linear", "limit" => "50" })

      results = ConnectorRegistryClient.search("linear")

      assert_equal [ "app.linear/linear", "io.github.Evozim/linear-broker" ], results.map { |m| m["name"] }
    end

    test "does not call out for a blank query" do
      assert_empty ConnectorRegistryClient.search(" ")
      assert_not_requested :get, %r{#{BASE}}
    end

    # --------------------------------------------------------------------- sync

    test "walks every page, following the opaque cursor verbatim" do
      cursor = "io.github.Evozim/linear-broker:1.0.0"
      stub_json(SERVERS_URL, list_body([ fixture_entry("remote_dual_transport") ], next_cursor: cursor),
                query: { "limit" => "100", "version" => "latest" })
      stub_json(SERVERS_URL, list_body([ fixture_entry("remote_secret_header") ]),
                query: { "limit" => "100", "version" => "latest", "cursor" => cursor })

      names = []
      count = ConnectorRegistryClient.each_updated_since { |page| names.concat(page.map { |m| m["name"] }) }

      assert_equal 2, count
      assert_equal [ "app.linear/linear", "io.github.Evozim/linear-broker" ], names
    end

    test "sends updated_since as an RFC 3339 timestamp so deletions are included" do
      timestamp = Time.utc(2026, 7, 30, 12, 0, 0)
      stub_json(SERVERS_URL, list_body([ fixture_entry("remote_dual_transport") ]),
                query: { "limit" => "100", "version" => "latest", "updated_since" => "2026-07-30T12:00:00.000Z" })

      assert_equal 1, ConnectorRegistryClient.each_updated_since(timestamp) { |_page| nil }
    end

    test "stops at the first empty page" do
      stub_json(SERVERS_URL, list_body([]), query: { "limit" => "100", "version" => "latest" })

      pages = 0

      assert_equal 0, ConnectorRegistryClient.each_updated_since { |_p| pages += 1 }
      assert_equal 0, pages
    end

    test "skips an unnormalizable entry rather than abandoning the page" do
      stub_json(SERVERS_URL, list_body([ "not-an-entry", fixture_entry("remote_dual_transport") ]),
                query: { "limit" => "100", "version" => "latest" })

      names = []
      ConnectorRegistryClient.each_updated_since { |page| names.concat(page.map { |m| m["name"] }) }

      assert_equal [ "app.linear/linear" ], names, "one bad publisher record must not stall the whole mirror"
    end

    # A walk crosses ~200 pages; one slow one must not discard the rest.
    test "retries a page before giving up on the walk" do
      stub_request(:get, SERVERS_URL).with(query: { "limit" => "100", "version" => "latest" })
                                     .to_timeout.then
                                     .to_return(status: 200,
                                                body: list_body([ fixture_entry("remote_dual_transport") ]),
                                                headers: { "Content-Type" => "application/json" })

      names = []
      ConnectorRegistryClient.each_updated_since { |page| names.concat(page.map { |m| m["name"] }) }

      assert_equal [ "app.linear/linear" ], names
    end

    # A failed request is not the end of the registry. Reporting it as one would
    # silently truncate the mirror while looking like a clean, complete sync.
    test "raises rather than pretending the registry simply ended" do
      stub_request(:get, %r{#{SERVERS_URL}}).to_return(status: 500)

      assert_raises(ConnectorRegistryClient::WalkInterrupted) do
        ConnectorRegistryClient.each_updated_since { |_p| flunk("should not yield") }
      end
    end

    test "keeps the pages it already walked when a later one fails" do
      cursor = "app.linear/linear:1.0.0"
      stub_json(SERVERS_URL, list_body([ fixture_entry("remote_dual_transport") ], next_cursor: cursor),
                query: { "limit" => "100", "version" => "latest" })
      stub_request(:get, SERVERS_URL).with(query: { "limit" => "100", "version" => "latest", "cursor" => cursor })
                                     .to_return(status: 503)

      names = []

      assert_raises(ConnectorRegistryClient::WalkInterrupted) do
        ConnectorRegistryClient.each_updated_since { |page| names.concat(page.map { |m| m["name"] }) }
      end
      assert_equal [ "app.linear/linear" ], names
    end

    # ------------------------------------------------------------------ config

    test "targets a configured subregistry when one is set" do
      Settings.mcp_registry.base_url = "https://registry.internal.example.com"
      stub_json("https://registry.internal.example.com/v0.1/servers/app.linear%2Flinear/versions/latest",
                fixture_entry("single_version_response").to_json)

      assert_equal "app.linear/linear", ConnectorRegistryClient.fetch("app.linear/linear")["name"]
    ensure
      Settings.mcp_registry.base_url = nil
    end
  end
end
