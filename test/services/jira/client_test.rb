# frozen_string_literal: true

require "test_helper"

class Jira::ClientTest < ActiveSupport::TestCase
  class RecordingCredential
    attr_reader :invalidations

    def initialize(tokens)
      @tokens = tokens
      @invalidations = 0
    end

    def authorization_headers = { "Authorization" => "Bearer #{@tokens.first}" }

    def invalidate!
      @invalidations += 1
      @tokens.shift
    end
  end

  def client(tokens = [ "t1" ])
    @credential = RecordingCredential.new(tokens)
    Jira::Client.new(cloud_id: "cloud-1", credential: @credential, retry_delay: 0)
  end

  test "each path segment is encoded on its own under the site's gateway path" do
    stub_request(:get, "#{jira_url('cloud-1', 'api', '2', 'issue', 'ENG-1%2F..%3Fx')}?fields=summary")
      .with(headers: { "Authorization" => "Bearer t1" }).to_return(status: 200, body: { id: "1" }.to_json)

    assert_equal({ "id" => "1" }, client.get("api", "2", "issue", "ENG-1/..?x", params: { fields: "summary" }))
  end

  test "a refused token is renewed once and the request repeated" do
    stub_request(:get, jira_url("cloud-1", "api", "2", "myself")).with(headers: { "Authorization" => "Bearer t1" }).to_return(status: 401)
    stub_request(:get, jira_url("cloud-1", "api", "2", "myself")).with(headers: { "Authorization" => "Bearer t2" })
                                                                   .to_return(status: 200, body: { accountId: "a" }.to_json)

    assert_equal "a", client(%w[t1 t2]).get("api", "2", "myself")["accountId"]
    assert_equal 1, @credential.invalidations
  end

  test "Jira's error envelope becomes the message, with the code callers branch on" do
    stub_request(:post, jira_url("cloud-1", "api", "2", "issue"))
      .to_return(status: 400, body: { errorMessages: [], errors: { summary: "You must specify a summary of the issue." } }.to_json)
    stub_request(:get, jira_url("cloud-1", "api", "2", "issue", "ENG-9")).to_return(status: 404, body: { errorMessages: [ "Issue does not exist" ] }.to_json)

    error = assert_raises(Jira::Error) { client.post("api", "2", "issue", body: { fields: {} }) }
    assert_equal [ "validation_failed", "summary: You must specify a summary of the issue." ], [ error.code, error.message ]
    assert_equal({ "summary" => "You must specify a summary of the issue." }, error.details)
    assert_equal "not_found", assert_raises(Jira::Error) { client.get("api", "2", "issue", "ENG-9") }.code
  end

  test "a throttled read is retried after Retry-After; a throttled write is not" do
    stub_request(:get, jira_url("cloud-1", "api", "2", "myself"))
      .to_return({ status: 429, headers: { "Retry-After" => "0" } }, { status: 200, body: "{}" })
    stub_request(:post, jira_url("cloud-1", "api", "2", "issue")).to_return(status: 429, headers: { "Retry-After" => "0" })

    assert_equal({}, client.get("api", "2", "myself"))
    assert_equal "rate_limited", assert_raises(Jira::Error) { client.post("api", "2", "issue", body: {}) }.code
  end

  test "a write that met a server error or a timeout may have landed" do
    stub_request(:post, jira_url("cloud-1", "api", "2", "issue", "1", "comment")).to_return(status: 502)
    stub_request(:put, jira_url("cloud-1", "api", "2", "issue", "1")).to_timeout
    stub_request(:get, jira_url("cloud-1", "api", "2", "issue", "1")).to_return({ status: 503 }, { status: 200, body: "{}" })

    assert_raises(Jira::Error::OutcomeUnknown) { client.post("api", "2", "issue", "1", "comment", body: { body: "x" }) }
    assert_raises(Jira::Error::OutcomeUnknown) { client.put("api", "2", "issue", "1", body: {}) }
    assert_equal({}, client.get("api", "2", "issue", "1"))
  end
end
