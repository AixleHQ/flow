# frozen_string_literal: true

require "test_helper"

# Rack::Attack is off in the test env; these turn it on against a private store.
class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    @previous_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
  end

  teardown do
    Rack::Attack.enabled = false
    Rack::Attack.cache.store = @previous_store
  end

  test "guessing invitation tokens from one address is cut off" do
    30.times { get "/invitations/not-a-token" }
    assert_not_equal 429, response.status

    get "/invitations/not-a-token"

    assert_response :too_many_requests
  end

  test "a generic webhook source is capped per endpoint, whichever address it posts from" do
    60.times { |i| post "/webhooks/in/some-slug", env: { "REMOTE_ADDR" => "203.0.113.#{i % 250}" } }
    assert_not_equal 429, response.status

    post "/webhooks/in/some-slug", env: { "REMOTE_ADDR" => "198.51.100.7" }
    assert_response :too_many_requests

    post "/webhooks/in/another-slug", env: { "REMOTE_ADDR" => "198.51.100.7" }
    assert_not_equal 429, response.status
  end

  test "MCP calls are counted per credential, and the count never keys on the raw credential" do
    one = rack_request({ "HTTP_X_SESSION_KEY" => "123.abc" })
    same_as_bearer = rack_request({ "HTTP_AUTHORIZATION" => "Bearer 123.abc" })
    other = rack_request({ "HTTP_X_SESSION_KEY" => "456.def" })

    assert_equal Rack::Attack.mcp_credential(one), Rack::Attack.mcp_credential(same_as_bearer)
    assert_not_equal Rack::Attack.mcp_credential(one), Rack::Attack.mcp_credential(other)
    assert_not_includes Rack::Attack.mcp_credential(one), "123.abc"
    assert_nil Rack::Attack.mcp_credential(rack_request({}))
  end

  test "member invites and re-sends are what the invite limit counts" do
    assert Rack::Attack.member_invite?(rack_request({}, method: "POST", path: "/company/members"))
    assert Rack::Attack.member_invite?(rack_request({}, method: "POST", path: "/company/members/12/resend"))
    assert_not Rack::Attack.member_invite?(rack_request({}, method: "PATCH", path: "/company/members/12"))
    assert_not Rack::Attack.member_invite?(rack_request({}, method: "GET", path: "/company/members"))
  end

  private

  def rack_request(headers, method: "POST", path: "/mcp")
    Rack::Attack::Request.new(Rack::MockRequest.env_for(path, { method: method }.merge(headers)))
  end
end
