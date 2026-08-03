# frozen_string_literal: true

require "test_helper"

module MCP
  # Sociable service tests on the real DB (testing doctrine R5): the real
  # Connector model, the real normalizer, real SQL. Only the network boundary is
  # faked, and it is faked with WebMock at the HTTP layer rather than by stubbing
  # ConnectorRegistryClient — the client's own contract tests pin its behaviour,
  # so exercising it for real here keeps the two from drifting apart.
  class ConnectorCatalogSyncTest < ActiveSupport::TestCase
    SERVERS_URL = "https://registry.modelcontextprotocol.io/v0.1/servers"

    def fixture_entry(name)
      JSON.parse(file_fixture("mcp_registry/#{name}.json").read)
    end

    def stub_page(entries, query:, next_cursor: nil)
      body = { "servers" => entries, "metadata" => { "count" => entries.size, "nextCursor" => next_cursor }.compact }
      stub_request(:get, SERVERS_URL).with(query: query)
                                     .to_return(status: 200, body: body.to_json,
                                                headers: { "Content-Type" => "application/json" })
    end

    test "mirrors registry entries as searchable connectors" do
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" })

      result = ConnectorCatalogSync.call

      assert_equal 1, result.fetched
      assert_equal 1, result.upserted
      connector = Connector.find_by(name: "app.linear/linear")
      assert_equal "MCP server for Linear project management and issue tracking", connector.description
      assert_equal "http", connector.manifest["targets"].first["transport"]
      assert_includes Connector.search("issue tracking"), connector
    end

    test "records the registry's own timestamp, not our write time" do
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call

      assert_equal "2025-09-18T15:51:15.598862Z", Connector.sole.registry_updated_at.utc.iso8601(6)
    end

    test "is idempotent — a second run updates rather than duplicates" do
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" })
      ConnectorCatalogSync.call(full: true)

      assert_difference -> { Connector.count }, 0 do
        ConnectorCatalogSync.call(full: true)
      end
    end

    test "resumes from the newest mirrored change, with an overlap so nothing slips through" do
      create(:connector, registry_updated_at: Time.utc(2026, 7, 30, 12, 0, 0),
                         normalizer_version: MCP::ConnectorManifest::VERSION.to_s)
      stub = stub_page([], query: { "limit" => "100", "version" => "latest", "updated_since" => "2026-07-30T11:00:00.000Z" })

      ConnectorCatalogSync.call

      assert_requested stub
    end

    test "walks the whole registry when nothing is mirrored yet" do
      stub = stub_page([], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call

      assert_requested stub, times: 1
    end

    test "full sync ignores the watermark" do
      create(:connector, registry_updated_at: Time.utc(2026, 7, 30, 12, 0, 0))
      stub = stub_page([], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call(full: true)

      assert_requested stub
    end

    test "follows pagination across pages" do
      cursor = "app.linear/linear:1.0.0"
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" }, next_cursor: cursor)
      stub_page([ fixture_entry("packages_pypi_and_mcpb") ], query: { "limit" => "100", "version" => "latest", "cursor" => cursor })

      result = ConnectorCatalogSync.call

      assert_equal 2, result.upserted
      assert_equal 2, Connector.count
    end

    test "mirrors a deleted entry instead of dropping it, so installs can still be warned" do
      entry = fixture_entry("remote_dual_transport")
      entry["_meta"]["io.modelcontextprotocol.registry/official"]["status"] = "deleted"
      stub_page([ entry ], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call

      connector = Connector.sole

      assert_predicate connector, :deleted?
      assert_not_includes Connector.discoverable, connector
    end

    test "treats an unrecognised upstream status as deprecated rather than healthy" do
      entry = fixture_entry("remote_dual_transport")
      entry["_meta"]["io.modelcontextprotocol.registry/official"]["status"] = "quarantined"
      stub_page([ entry ], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call

      assert_predicate Connector.sole, :deprecated?
    end

    test "updates an existing mirror row in place" do
      create(:connector, name: "app.linear/linear", title: "Stale", description: "Stale copy")
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call(full: true)

      connector = Connector.sole

      assert_nil connector.title, "the live payload has no title; the stale one must not survive"
      assert_equal "MCP server for Linear project management and issue tracking", connector.description
    end

    test "skips an entry with no name rather than writing a nameless row" do
      stub_page([ { "server" => { "description" => "nameless" } }, fixture_entry("remote_dual_transport") ],
                query: { "limit" => "100", "version" => "latest" })

      result = ConnectorCatalogSync.call

      assert_equal 2, result.fetched
      assert_equal 1, result.upserted
      assert_equal [ "app.linear/linear" ], Connector.pluck(:name)
    end

    test "refreshes install counts so the catalog can rank by real usage" do
      company = create(:company)
      user = create(:user, company: company)
      project = create(:project, company: company, owner: user)
      project.mcp_servers.create!(name: "Linear", url: "https://mcp.linear.app/mcp", transport: :http,
                                  connector_name: "app.linear/linear")
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call

      assert_equal 1, Connector.find_by(name: "app.linear/linear").install_count
    end

    test "clears a stale install count when the last install is gone" do
      create(:connector, name: "app.linear/linear", install_count: 7)
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call(full: true)

      assert_equal 0, Connector.sole.install_count
    end

    test "marks the curated seed list so a cold catalog opens on something useful" do
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call

      assert_predicate Connector.find_by(name: "app.linear/linear"), :featured?
    end

    test "unmarks a connector dropped from the curated list" do
      create(:connector, name: "io.github.someone/retired", featured: true)
      stub_page([], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call(full: true)

      assert_not Connector.find_by(name: "io.github.someone/retired").featured?
    end

    # The registry carries every version of every server; asking for latest only
    # is what keeps one product from occupying five catalog cards.
    test "asks the registry for latest versions only" do
      stub = stub_page([], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call

      assert_requested stub
    end

    test "survives a page that carries the same server twice" do
      duplicate = fixture_entry("remote_dual_transport")
      stub_page([ duplicate, duplicate ], query: { "limit" => "100", "version" => "latest" })

      result = ConnectorCatalogSync.call

      assert_equal 2, result.fetched
      assert_equal 0, result.failed, "Postgres refuses an upsert touching one row twice; the page must be deduped"
      assert_equal 1, Connector.count
    end

    test "marks namespaces that publish at scale, from the mirror itself" do
      Connector::BULK_PUBLISHER_THRESHOLD.times { |i| create(:connector, name: "io.github.farm/thing-#{i}") }
      lone = create(:connector, name: "com.vendor/product")
      stub_page([], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call(full: true)

      assert Connector.find_by(name: "io.github.farm/thing-0").bulk_publisher?
      assert_not lone.reload.bulk_publisher?
    end

    # The normalizer's output is stored, so a change on our side must reach rows
    # the registry never touched again — an incremental sync alone would skip them.
    test "re-walks everything when the mirror was built by an older normalizer" do
      create(:connector, registry_updated_at: 1.day.ago, normalizer_version: "1")
      stub = stub_page([], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call

      assert_requested stub, times: 1
    end

    test "stays incremental when the whole mirror is current" do
      create(:connector, registry_updated_at: Time.utc(2026, 7, 30, 12, 0, 0),
                         normalizer_version: MCP::ConnectorManifest::VERSION.to_s)
      stub = stub_page([], query: { "limit" => "100", "version" => "latest",
                                    "updated_since" => "2026-07-30T11:00:00.000Z" })

      ConnectorCatalogSync.call

      assert_requested stub
    end

    test "records which normalizer built each mirrored row" do
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" })

      ConnectorCatalogSync.call

      assert_equal MCP::ConnectorManifest::VERSION.to_s, Connector.sole.normalizer_version
    end

    test "a registry outage leaves the existing mirror untouched and is reported, not swallowed" do
      existing = create(:connector)
      stub_request(:get, /#{Regexp.escape(SERVERS_URL)}/).to_return(status: 503)

      result = ConnectorCatalogSync.call

      assert_equal 0, result.fetched
      assert result.interrupted, "an aborted walk must not read as a completed one"
      assert_equal [ existing ], Connector.all.to_a
    end

    test "keeps what it mirrored when the walk breaks part-way, and says the run was cut short" do
      cursor = "app.linear/linear:1.0.0"
      stub_page([ fixture_entry("remote_dual_transport") ], query: { "limit" => "100", "version" => "latest" },
                next_cursor: cursor)
      stub_request(:get, SERVERS_URL).with(query: { "limit" => "100", "version" => "latest", "cursor" => cursor })
                                     .to_return(status: 503)

      result = ConnectorCatalogSync.call

      assert_equal 1, result.upserted
      assert result.interrupted
      assert_equal 1, Connector.count
    end
  end
end
