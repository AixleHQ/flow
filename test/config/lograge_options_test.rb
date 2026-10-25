# frozen_string_literal: true

require "test_helper"

class LogrageOptionsTest < ActiveSupport::TestCase
  Event = Struct.new(:name, :payload)

  def options_for(path, params = { "files" => { "/home/claude/.claude/.credentials.json" => "{\"refreshToken\":\"rt\"}" } }, **payload)
    Rails.application.config.lograge.custom_options.call(
      Event.new("process_action.action_controller", { path: path, params: params, host: "x", ip: nil, ff: nil, **payload })
    )
  end

  test "the MCP and credential endpoints log who called, never their params" do
    %w[/mcp /action_mcp /agents/credentials /agents/credentials/refresh /cloud/aws/credentials /azure/git/credentials].each do |path|
      assert_not options_for(path).key?(:params), "#{path} logged its params"
    end

    logged = options_for("/action_mcp", session: 42)
    assert_equal 42, logged[:session]
  end

  test "other requests log their (filtered) params and their user" do
    logged = options_for("/company/projects", { "name" => "p" }, user: 7)

    assert_equal({ "name" => "p" }, logged[:params])
    assert_equal 7, logged[:user]
  end
end
