# frozen_string_literal: true

require "test_helper"

# Contract test of the partner API as Insights specifies it — and of the shapes
# FakeInsightsClient returns.
module Insights
  class ClientTest < ActiveSupport::TestCase
    BASE = "https://insights.example.com"

    setup { @client = Client.new(url: BASE) }

    test "claim redeems the code with the deployment credential and returns the connection" do
      stub = stub_request(:post, "#{BASE}/partner/v1/connections/claim")
             .with(basic_auth: %w[dep-1 dep-secret],
                   body: { code: "ABCD2345", company: { id: 7, name: "Acme Co" } }.to_json)
             .to_return(status: 201, body: { connection_id: "conn-1", secret: "aixle_flow_s1",
                                             organization: { id: "org-1", name: "Acme" } }.to_json)

      result = @client.claim(code: "abcd-2345".upcase, company_id: 7, company_name: "Acme Co",
                             deployment_id: "dep-1", deployment_secret: "dep-secret")

      assert_requested stub
      assert_equal({ connection_id: "conn-1", secret: "aixle_flow_s1", organization_id: "org-1",
                     organization_name: "Acme" }, result)
      assert_equal result.keys.sort,
                   FakeInsightsClient.new.claim(code: "x", company_id: 1, company_name: "x", deployment_id: "d",
                                                deployment_secret: "s").keys.sort
    end

    test "a refused code raises with Insights' status and error" do
      stub_request(:post, "#{BASE}/partner/v1/connections/claim").to_return(status: 422, body: { error: "invalid_code" }.to_json)

      error = assert_raises(Client::Error) do
        @client.claim(code: "x", company_id: 1, company_name: "x", deployment_id: "d", deployment_secret: "s")
      end
      assert_equal [ 422, "invalid_code" ], [ error.status, error.code ]
    end

    test "the connection's own secret lists projects, rotates and disconnects" do
      auth = { "Authorization" => "Bearer aixle_flow_s1" }
      stub_request(:get, "#{BASE}/partner/v1/connection/projects").with(headers: auth)
                                                                  .to_return(status: 200, body: { projects: [ { id: "p1", name: "Web" } ] }.to_json)
      stub_request(:post, "#{BASE}/partner/v1/connection/rotate").with(headers: auth)
                                                                 .to_return(status: 200, body: { secret: "aixle_flow_s2" }.to_json)
      stub_request(:delete, "#{BASE}/partner/v1/connection").with(headers: auth).to_return(status: 204)

      assert_equal [ { "id" => "p1", "name" => "Web" } ], @client.projects("aixle_flow_s1")
      assert_equal "aixle_flow_s2", @client.rotate("aixle_flow_s1")
      assert @client.disconnect("aixle_flow_s1")
    end

    test "disconnecting with a secret Insights no longer accepts counts as done" do
      stub_request(:delete, "#{BASE}/partner/v1/connection").to_return(status: 401, body: { error: "unauthorized" }.to_json)

      assert @client.disconnect("aixle_flow_gone")
    end

    test "a logs chunk is sent gzipped, and the OTLP partial success is read" do
      stub = stub_request(:post, "#{BASE}/partner/v1/aixle_flow/logs")
             .with(headers: { "Content-Encoding" => "gzip", "Authorization" => "Bearer aixle_flow_s1" }) do |request|
               JSON.parse(Zlib.gunzip(request.body)) == { "resourceLogs" => [] }
             end
             .to_return(status: 200, body: { partialSuccess: { rejectedLogRecords: "2", errorMessage: "record 3: bad" } }.to_json)

      result = @client.export_logs("aixle_flow_s1", { "resourceLogs" => [] })

      assert_requested stub
      assert_equal [ 200, 2, "record 3: bad" ], [ result.status, result.rejected, result.message ]
      assert result.partially_rejected?
      assert_not result.accepted?
    end

    test "a rate-limited chunk carries Retry-After" do
      stub_request(:post, "#{BASE}/partner/v1/aixle_flow/logs").to_return(status: 429, headers: { "Retry-After" => "30" })

      result = @client.export_logs("s", {})

      assert_equal [ 429, 30 ], [ result.status, result.retry_after ]
    end

    test "an unreachable Insights raises" do
      stub_request(:get, "#{BASE}/partner/v1/connection/projects").to_raise(SocketError)

      assert_raises(Client::Error) { @client.projects("s") }
    end
  end
end
