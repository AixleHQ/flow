# frozen_string_literal: true

require "test_helper"

# Each process draws only the routes it serves (config/routes.rb,
# docs/design/agent-runtimes/DESIGN.md §6.1): the runner gateway's Puma routes
# /runner/v1/* and /up and nothing else, and every other process routes
# everything else, MCP included, but not /runner/v1/*.
class ProcessModeRoutesTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper

  GATEWAY_ENDPOINTS = [ %w[POST /runner/v1/register], %w[DELETE /runner/v1/registration], %w[POST /runner/v1/token] ].freeze

  test "outside the gateway, /runner/v1/* is not routed and MCP still is" do
    GATEWAY_ENDPOINTS.each do |verb, path|
      assert_not routed?(verb, path), "#{verb} #{path} should not route outside the gateway"
    end
    assert routed?("POST", "/mcp")
    assert routed?("POST", "/action_mcp")
    assert routed?("GET", "/up")

    post "/runner/v1/register", headers: { "X-Aixle-Runner-Protocol" => "1" }
    assert_response :not_found
  end

  test "inside the gateway, only /runner/v1/* and /up are routed" do
    with_process_mode("runner_gateway") do
      paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s.delete_suffix("(.:format)") }

      assert_equal [ "/up" ], paths.reject { |path| path.start_with?("/runner/v1/") }
      GATEWAY_ENDPOINTS.each { |verb, path| assert routed?(verb, path), "#{verb} #{path} should route in the gateway" }
      assert_not routed?("POST", "/mcp")

      post "/mcp"
      assert_response :not_found
    end
  end

  private

  def routed?(verb, path)
    Rails.application.routes.recognize_path(path, method: verb)
    true
  rescue ActionController::RoutingError
    false
  end
end
