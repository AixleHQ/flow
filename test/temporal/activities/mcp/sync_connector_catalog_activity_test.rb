# frozen_string_literal: true

require "test_helper"

class Activities::MCP::SyncConnectorCatalogActivityTest < ActiveSupport::TestCase
  SERVERS_URL = "https://registry.modelcontextprotocol.io/v0.1/servers"

  setup do
    Rails.logger.stubs(:info)
  end

  def stub_page(entries, query:)
    body = { "servers" => entries, "metadata" => { "count" => entries.size } }
    stub_request(:get, SERVERS_URL).with(query: query)
                                   .to_return(status: 200, body: body.to_json,
                                              headers: { "Content-Type" => "application/json" })
  end

  def registry_entry
    JSON.parse(file_fixture("mcp_registry/remote_dual_transport.json").read)
  end

  test "mirrors the registry and reports what it wrote" do
    stub_page([ registry_entry ], query: { "limit" => "100", "version" => "latest" })

    result = run_activity(Activities::MCP::SyncConnectorCatalogActivity)

    assert_equal({ fetched: 1, upserted: 1, failed: 0 }, result)
    assert_equal [ "app.linear/linear" ], Connector.pluck(:name)
  end

  test "runs incrementally by default, resuming from the newest mirrored change" do
    create(:connector, registry_updated_at: Time.utc(2026, 7, 30, 12, 0, 0))
    stub = stub_page([], query: { "limit" => "100", "version" => "latest", "updated_since" => "2026-07-30T11:00:00.000Z" })

    run_activity(Activities::MCP::SyncConnectorCatalogActivity)

    assert_requested stub
  end

  test "a full rebuild is requestable for when the registry resets its data" do
    create(:connector, registry_updated_at: Time.utc(2026, 7, 30, 12, 0, 0))
    stub = stub_page([ registry_entry ], query: { "limit" => "100", "version" => "latest" })

    run_activity(Activities::MCP::SyncConnectorCatalogActivity, { "full" => true })

    assert_requested stub
  end

  test "reports zero rather than raising when the registry is down" do
    stub_request(:get, /#{Regexp.escape(SERVERS_URL)}/).to_return(status: 503)

    result = run_activity(Activities::MCP::SyncConnectorCatalogActivity)

    assert_equal({ fetched: 0, upserted: 0, failed: 0 }, result)
  end
end
