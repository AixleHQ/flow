# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Contract test for the request construction and error mapping every service
  # inherits: fixed host, per-segment encoding, per-family api-version, and the
  # status translation that decides whether a failed write is "failed" or
  # "unknown".
  class ClientTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_enabled
      @integration = create(:integration, :azure_devops, :active)
      stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
      @client, @resolved = CredentialProvider.client_for(@integration)
    end

    test "encodes every path segment separately and picks the family's api-version" do
      stub = stub_request(:get, "#{AZURE_API_HOST}/#{@resolved.organization}/Customer%20Platform/_apis/git/repositories")
             .with(query: { "api-version" => "7.1" })
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { value: [] }.to_json)

      @client.get("_apis", "git", "repositories", family: :git, project: "Customer Platform")

      assert_requested stub
    end

    test "work item comments use their own preview version, not the GA one" do
      stub = stub_request(:get, "#{AZURE_API_HOST}/#{@resolved.organization}/proj/_apis/wit/workItems/7/comments")
             .with(query: { "api-version" => "7.1-preview.4" })
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { comments: [] }.to_json)

      @client.get("_apis", "wit", "workItems", 7, "comments", family: :wit_comments, project: "proj")

      assert_requested stub
    end

    test "a path segment cannot smuggle a separator or a traversal" do
      stub = stub_request(:get, "#{AZURE_API_HOST}/#{@resolved.organization}/_apis/git/repositories/..%2F..%2Fadmin")
             .with(query: { "api-version" => "7.1" })
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: "{}")

      @client.get("_apis", "git", "repositories", "../../admin", family: :git)

      assert_requested stub
    end

    test "a 401 reacquires the token once and retries once" do
      token_stub = stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
      call_count = 0
      stub_request(:get, %r{/_apis/test}).to_return do
        call_count += 1
        call_count == 1 ? { status: 401, body: "" } : { status: 200, headers: { "Content-Type" => "application/json" }, body: "{}" }
      end

      @client.get("_apis", "test")

      assert_equal 2, call_count
      assert_requested token_stub, at_least_times: 1
    end

    test "a second 401 is an authorization failure, not another retry" do
      stub_request(:get, %r{/_apis/test}).to_return(status: 401, body: "")

      assert_raises(NotAuthorized) { @client.get("_apis", "test") }
    end

    test "maps Azure statuses onto the adapter's stable codes" do
      {
        403 => PermissionDenied,
        404 => NotFound,
        409 => Conflict,
        400 => ValidationFailed
      }.each do |status, klass|
        stub_request(:get, %r{/_apis/case-#{status}}).to_return(
          status: status, headers: { "Content-Type" => "application/json" },
          body: { message: "Azure says no" }.to_json
        )

        assert_raises(klass) { @client.get("_apis", "case-#{status}") }
      end
    end

    test "a 429 carries Azure's own delay rather than a guessed quota" do
      stub_request(:post, %r{/_apis/throttled}).to_return(status: 429, headers: { "Retry-After" => "7" }, body: "")

      error = assert_raises(RateLimited) { @client.post("_apis", "throttled", body: {}) }
      assert_in_delta 7.0, error.retry_after, 0.01
    end

    test "a timed-out write is unknown, and a timed-out read is merely a timeout" do
      stub_request(:post, %r{/_apis/slow}).to_timeout
      stub_request(:get, %r{/_apis/slow}).to_timeout

      assert_raises(OutcomeUnknown) { @client.post("_apis", "slow", body: {}) }
      read_error = assert_raises(Error) { @client.get("_apis", "slow") }
      assert_equal "timeout", read_error.code
    end

    test "a 500 on a write is unknown rather than retried" do
      stub = stub_request(:post, %r{/_apis/boom}).to_return(status: 500, body: "")

      assert_raises(OutcomeUnknown) { @client.post("_apis", "boom", body: {}) }
      # Exactly once: a POST that got a 500 may already have been applied.
      assert_requested stub, times: 1
    end

    test "paginate follows Azure's continuation header and stops at the limit" do
      base = "#{AZURE_API_HOST}/#{@resolved.organization}/_apis/paged"
      stub_request(:get, base).with(query: { "api-version" => "7.1" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json", "x-ms-continuationtoken" => "page2" },
                   body: { value: [ { id: 1 } ] }.to_json)
      stub_request(:get, base).with(query: { "api-version" => "7.1", "continuationToken" => "page2" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { value: [ { id: 2 } ] }.to_json)

      items, more = @client.paginate("_apis", "paged", limit: 10)

      assert_equal [ 1, 2 ], items.map { |i| i["id"] }
      refute more
    end
  end
end
