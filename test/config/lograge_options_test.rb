# frozen_string_literal: true

require "test_helper"

class LogrageOptionsTest < ActiveSupport::TestCase
  Event = Struct.new(:name, :payload)

  def options_for(path, params = { "files" => { "/home/claude/.claude/.credentials.json" => "{\"refreshToken\":\"rt\"}" } })
    Rails.application.config.lograge.custom_options.call(
      Event.new("process_action.action_controller", { path: path, params: params, host: "x", ip: nil, ff: nil })
    )
  end

  test "the MCP and credential endpoints never log their params" do
    %w[/mcp /action_mcp /agents/credentials /cloud/aws/credentials /azure/git/credentials].each do |path|
      assert_nil options_for(path), "#{path} logged its params"
    end
  end

  test "other requests log their (filtered) params" do
    logged = options_for("/company/projects", { "name" => "p" })

    assert_equal({ "name" => "p" }, logged[:params])
  end
end
