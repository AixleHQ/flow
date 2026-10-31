# frozen_string_literal: true

require "open3"
require "test_helper"

# Each process draws only the routes it serves (config/routes.rb,
# docs/design/agent-runtimes/DESIGN.md §6.1): the runner gateway's Puma routes
# /runner/v1/* and /up and nothing else, and every other process routes
# everything else, MCP included, but not /runner/v1/*.
class ProcessModeRoutesTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper

  GATEWAY_ENDPOINTS = [
    %w[POST /runner/v1/register], %w[DELETE /runner/v1/registration], %w[POST /runner/v1/token],
    %w[GET /runner/v1/ops], %w[POST /runner/v1/ops/1/result]
  ].freeze
  GATEWAY_PATHS = [
    "/up", "/runner/v1/register", "/runner/v1/registration", "/runner/v1/token", "/runner/v1/ops",
    "/runner/v1/ops/:id/result"
  ].freeze

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
      # The framework's own routes were prepended when this process booted as
      # the web process; the next test boots as the gateway to cover them.
      assert_equal GATEWAY_PATHS, route_paths(Rails.application.routes.routes.reject(&:internal))
      GATEWAY_ENDPOINTS.each { |verb, path| assert routed?(verb, path), "#{verb} #{path} should route in the gateway" }
      assert_not routed?("POST", "/mcp")

      post "/mcp"
      assert_response :not_found
    end
  end

  # As config/puma_runner_gateway.rb boots it: the mode is set before the app
  # loads, so Action Cable does not mount /cable either (config/application.rb).
  # Inertia's devtools routes are drawn in every process and match only in
  # development (InertiaRails::Devtools.enabled?).
  test "a process booted as the gateway routes /runner/v1/* and /up only" do
    script = 'puts Rails.application.routes.routes.map { |route| route.path.spec.to_s }.join("\n")'
    output, status = Open3.capture2e({ "AIXLE_PROCESS_MODE" => "runner_gateway", "RAILS_ENV" => "test" },
                                     Rails.root.join("bin/rails").to_s, "runner", script, chdir: Rails.root.to_s)

    assert status.success?, output
    paths = output.lines.map(&:strip).grep(%r{\A/}).map { |path| path.delete_suffix("(.:format)") }
    assert_equal GATEWAY_PATHS, paths.reject { |path| path.start_with?("/_inertia/devtools/") }
  end

  private

  def route_paths(routes)
    routes.map { |route| route.path.spec.to_s.delete_suffix("(.:format)") }
  end

  def routed?(verb, path)
    Rails.application.routes.recognize_path(path, method: verb)
    true
  rescue ActionController::RoutingError
    false
  end
end
