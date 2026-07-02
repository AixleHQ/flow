# frozen_string_literal: true

require "test_helper"

# Guards the assumptions of config/initializers/action_mcp_dynamic_tools.rb,
# which replaces ActionMCP::Server::Tools handlers wholesale. These tests fail
# loudly on a gem upgrade so the patch gets re-verified instead of silently
# breaking at runtime (the gem's tool dispatcher calls our overrides with a
# version-specific argument list).
class ActionMcpPatchGuardTest < ActiveSupport::TestCase
  PINNED_REQUIREMENT = Gem::Requirement.create("~> 0.104.0")

  UPGRADE_NOTES = <<~MSG
    actionmcp was upgraded past the range the dynamic-tools monkey-patch was
    written against. Before bumping the pin, re-verify against the new gem
    internals (config/initializers/action_mcp_dynamic_tools.rb):
      - send_tools_call arity (0.111 adds a 5th task_params argument)
      - send_tools_list cursor pagination (added in 0.109)
      - consent gate (-32002), strict-param -32602, task-augmented calls —
        all bypassed by the wholesale override
      - dropped MCP protocol versions (0.111 removed 2025-03-26)
    Then update PINNED_REQUIREMENT here and the Gemfile comment.
  MSG

  test "actionmcp version stays within the range the patch was written for" do
    version = Gem.loaded_specs["actionmcp"].version
    assert PINNED_REQUIREMENT.satisfied_by?(version),
           "actionmcp #{version} is outside #{PINNED_REQUIREMENT}.\n#{UPGRADE_NOTES}"
  end

  test "patched handler signatures match what the 0.104 dispatcher sends" do
    tools = ActionMCP::Server::Tools

    assert_equal [[:req, :request_id], [:opt, :params]],
                 tools.instance_method(:send_tools_list).parameters,
                 "send_tools_list signature drifted.\n#{UPGRADE_NOTES}"

    assert_equal [[:req, :request_id], [:req, :tool_name], [:req, :arguments], [:opt, :_meta]],
                 tools.instance_method(:send_tools_call).parameters,
                 "send_tools_call signature drifted.\n#{UPGRADE_NOTES}"
  end

  test "gateway identity extension is applied" do
    assert_includes ActionMCP.configuration.allowed_identity_keys, "terminal_session"
    assert ActionMCP::Current.respond_to?(:terminal_session),
           "ActionMCP::Current lost the terminal_session attribute the gateway relies on"
  end
end
