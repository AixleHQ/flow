# frozen_string_literal: true

require "test_helper"

module Engram
  class ClientTest < ActiveSupport::TestCase
    setup do
      @client = Client.new(url: "http://engram:7437")
      @observation = { "id" => 7, "title" => "Brief", "content" => "Verified context", "project" => "flow:company:1:project:2" }
    end

    test "search translates the private REST contract" do
      stub_request(:get, "http://engram:7437/search")
        .with(query: { q: "context & evidence", project: @observation["project"], scope: "project", limit: "3" })
        .to_return(body: [ @observation.merge("type" => "summary", "score" => 1.0) ].to_json)

      assert_equal [ @observation ], @client.search(project: @observation["project"], query: "context & evidence", limit: 3)
    end

    test "save registers an isolated project session and writes a canonical observation" do
      stub_request(:post, "http://engram:7437/sessions")
        .with { |request| JSON.parse(request.body).slice("project", "ownership_mode", "isolated") == { "project" => @observation["project"], "ownership_mode" => "project_owned", "isolated" => true } }
        .to_return(status: 201, body: { id: "flow-session", status: "created" }.to_json)
      stub_request(:post, "http://engram:7437/observations")
        .with(body: { session_id: "flow-session", project: @observation["project"], title: "Brief", content: "Verified context", topic_key: "brief:2", type: "summary", scope: "project", capture_prompt: false }.to_json)
        .to_return(status: 201, body: { id: 7, status: "saved" }.to_json)

      assert_equal 7, @client.save(project: @observation["project"], title: "Brief", content: "Verified context", topic_key: "brief:2")
    end

    test "delete hard purges only the expected project" do
      stub_request(:delete, "http://engram:7437/observations/7")
        .with(query: { hard: "true", expected_project: @observation["project"] })
        .to_return(body: { id: 7, status: "deleted", hard_delete: true }.to_json)

      assert @client.delete(id: 7, project: @observation["project"])
    end

    test "delete is idempotent when observation was already purged" do
      stub_request(:delete, %r{http://engram:7437/observations/7}).to_return(status: 404)

      assert @client.delete(id: 7, project: @observation["project"])
    end

    test "operator token authenticates private requests" do
      stub_request(:get, %r{http://engram:7437/search})
        .with(headers: { "Authorization" => "Bearer operator-secret" }).to_return(body: "[]")

      assert_equal [], Client.new(url: "http://engram:7437", token: "operator-secret").search(project: "p", query: "q", limit: 3)
    end

    test "fake shares save search delete contract without network" do
      fake = FakeEngramClient.new
      id = fake.save(project: @observation["project"], title: "Brief", content: "Verified context", topic_key: "brief:2")

      assert_kind_of Integer, id
      assert_equal [ @observation.merge("id" => id) ], fake.search(project: @observation["project"], query: "context", limit: 3)
      assert_equal [], fake.search(project: "other", query: "context", limit: 3)
      assert fake.delete(id: id, project: @observation["project"])
      assert_equal [], fake.search(project: @observation["project"], query: "context", limit: 3)
    end

    test "outages and invalid JSON expose only a sanitized error" do
      [ { status: 503, body: "secret upstream body" }, { status: 200, body: "invalid secret JSON" } ].each do |response|
        stub_request(:get, %r{http://engram:7437/search}).to_return(response)
        error = assert_raises(Client::Unavailable) { @client.search(project: "p", query: "secret query", limit: 3) }
        assert_equal "Project memory is unavailable", error.message
      end
    end

    test "redirect responses are rejected without following" do
      stub_request(:get, %r{http://engram:7437/search}).to_return(status: 302, headers: { "Location" => "http://elsewhere/private" })

      assert_raises(Client::Unavailable) { @client.search(project: "p", query: "q", limit: 3) }
      assert_not_requested :get, "http://elsewhere/private"
    end

    test "oversized responses are rejected while streaming" do
      stub_request(:get, %r{http://engram:7437/search}).to_return(body: "x" * 101)
      client = Client.new(url: "http://engram:7437", max_response_bytes: 100)

      assert_raises(Client::Unavailable) { client.search(project: "p", query: "q", limit: 3) }
    end

    test "timeout and malformed observations fail closed" do
      stub_request(:get, %r{http://engram:7437/search}).to_timeout
      assert_raises(Client::Unavailable) { @client.search(project: "p", query: "q", limit: 3) }

      stub_request(:get, %r{http://engram:7437/search}).to_return(body: [ { id: 7, content: "incomplete" } ].to_json)
      assert_raises(Client::Unavailable) { @client.search(project: "p", query: "q", limit: 3) }
    end

    test "configuration accepts only an origin" do
      [ "", "file:///private/data", "http://user:secret@engram:7437", "http://engram:7437/path", "http://engram:7437?secret=value" ].each do |url|
        assert_raises(Client::Unavailable) { Client.new(url: url) }
      end
    end
  end
end
