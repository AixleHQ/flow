# frozen_string_literal: true

require "test_helper"

module Bitbucket
  # Contract test for what every Bitbucket service inherits: the fixed host,
  # per-segment encoding, `page`-only pagination, and the status translation
  # that decides whether a failed write is "failed" or "unknown".
  class ClientTest < ActiveSupport::TestCase
    setup do
      with_bitbucket_settings
      @slept = []
      @client = Client.new(credential: Credential.new(token: "tok-1", kind: :access_token),
                           sleeper: ->(seconds) { @slept << seconds })
    end

    def json(body, status: 200, headers: {})
      { status: status, headers: { "Content-Type" => "application/json" }.merge(headers), body: body.to_json }
    end

    test "sends the token as a bearer and encodes every segment, braces included" do
      stub = stub_request(:get, "#{BITBUCKET_API}/repositories/%7Bws-uuid%7D/a%2Fb")
             .with(headers: { "Authorization" => "Bearer tok-1" })
             .to_return(json({ "slug" => "x" }))

      assert_equal({ "slug" => "x" }, @client.get("repositories", "{ws-uuid}", "a/b"))
      assert_requested stub
    end

    test "follows only the page parameter of the next link, on its own path" do
      stub_request(:get, "#{BITBUCKET_API}/repositories/acme")
        .with(query: { "pagelen" => "2" })
        .to_return(json({ "values" => [ 1, 2 ], "next" => "https://evil.example/2.0/x?page=2&pagelen=2" }))
      second = stub_request(:get, "#{BITBUCKET_API}/repositories/acme")
               .with(query: { "pagelen" => "2", "page" => "2" })
               .to_return(json({ "values" => [ 3 ] }))

      values, more = @client.paginate("repositories", "acme", params: { pagelen: 2 })

      assert_equal [ 1, 2, 3 ], values
      assert_not more
      assert_requested second
    end

    test "stops at the limit and says more were left" do
      stub_request(:get, "#{BITBUCKET_API}/repositories/acme")
        .to_return(json({ "values" => [ 1, 2, 3 ], "next" => "#{BITBUCKET_API}/repositories/acme?page=2" }))

      values, more = @client.paginate("repositories", "acme", limit: 2)

      assert_equal [ 1, 2 ], values
      assert more
    end

    # Found live: a pull request's diffstat answers 302 to a diffstat path on the
    # same API host.
    test "follows a read's redirect to another path on the API host" do
      stub_request(:get, "#{BITBUCKET_API}/repositories/ws/repo/pullrequests/1/diffstat")
        .to_return(status: 302, headers: { "Location" => "#{BITBUCKET_API}/repositories/ws/repo/diffstat/ws/repo:aaa%0Dbbb?from_pullrequest_id=1&topic=true" })
      target = stub_request(:get, "#{BITBUCKET_API}/repositories/ws/repo/diffstat/ws/repo:aaa%0Dbbb")
               .with(query: { "from_pullrequest_id" => "1", "topic" => "true" }, headers: { "Authorization" => "Bearer tok-1" })
               .to_return(json({ "values" => [ { "status" => "added" } ] }))

      assert_equal [ { "status" => "added" } ], @client.get("repositories", "ws", "repo", "pullrequests", 1, "diffstat")["values"]
      assert_requested target
    end

    test "refuses a redirect to another host, which would receive the token" do
      stub_request(:get, "#{BITBUCKET_API}/repositories/ws/repo/pullrequests/1/diffstat")
        .to_return(status: 302, headers: { "Location" => "https://evil.example/2.0/steal" })

      error = assert_raises(Error) { @client.get("repositories", "ws", "repo", "pullrequests", 1, "diffstat") }
      assert_equal "provider_error", error.code
    end

    test "a 401 is retried once with the credential's refresh, and never again" do
      fresh = Credential.new(token: "tok-2", kind: :app)
      client = Client.new(credential: Credential.new(token: "tok-1", kind: :app, refresher: -> { fresh }))
      stub_request(:get, "#{BITBUCKET_API}/user").with(headers: { "Authorization" => "Bearer tok-1" }).to_return(status: 401)
      second = stub_request(:get, "#{BITBUCKET_API}/user").with(headers: { "Authorization" => "Bearer tok-2" })
                                                          .to_return(status: 401)

      assert_raises(Error::NotAuthorized) { client.get("user") }
      assert_requested second, times: 1
    end

    test "a 401 with nothing to refresh to is not retried" do
      stub = stub_request(:get, "#{BITBUCKET_API}/user").to_return(status: 401)

      assert_raises(Error::NotAuthorized) { @client.get("user") }
      assert_requested stub, times: 1
    end

    test "maps Bitbucket's error envelope into validation details" do
      stub_request(:post, "#{BITBUCKET_API}/repositories/acme/api/pullrequests")
        .to_return(json({ "type" => "error",
                          "error" => { "message" => "Bad request", "fields" => { "source" => [ "not found" ] } } },
                        status: 400))

      error = assert_raises(Error::ValidationFailed) do
        @client.post("repositories", "acme", "api", "pullrequests", body: { title: "x" })
      end
      assert_equal "Bad request", error.message
      assert_equal({ "source" => [ "not found" ] }, error.details)
    end

    test "a read is retried after a 429, a write is not" do
      stub_request(:get, "#{BITBUCKET_API}/user")
        .to_return(json({}, status: 429, headers: { "Retry-After" => "3" })).then.to_return(json({ "uuid" => "u" }))
      stub_request(:post, "#{BITBUCKET_API}/repositories/acme/api/pullrequests/1/approve")
        .to_return(json({}, status: 429, headers: { "Retry-After" => "3" }))

      assert_equal({ "uuid" => "u" }, @client.get("user"))
      assert_equal [ 3.0 ], @slept
      error = assert_raises(Error::RateLimited) { @client.post("repositories", "acme", "api", "pullrequests", 1, "approve") }
      assert_in_delta(3.0, error.retry_after)
    end

    test "a 5xx on a write is an unknown outcome, never a failure" do
      stub_request(:post, "#{BITBUCKET_API}/repositories/acme/api/pullrequests").to_return(status: 502)

      assert_raises(Error::OutcomeUnknown) { @client.post("repositories", "acme", "api", "pullrequests", body: {}) }
    end

    test "a timeout on a write is an unknown outcome" do
      stub_request(:post, "#{BITBUCKET_API}/repositories/acme/api/pullrequests").to_timeout

      assert_raises(Error::OutcomeUnknown) { @client.post("repositories", "acme", "api", "pullrequests", body: {}) }
    end

    test "a raw response carries the status, for endpoints that answer 202" do
      stub_request(:post, "#{BITBUCKET_API}/repositories/acme/api/pullrequests/1/merge")
        .to_return(json({ "task_id" => "t1" }, status: 202))

      response = @client.post("repositories", "acme", "api", "pullrequests", 1, "merge", body: {}, raw: true)

      assert_equal 202, response.status
      assert_equal "t1", response.body["task_id"]
    end
  end
end
