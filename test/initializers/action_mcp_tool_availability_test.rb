# frozen_string_literal: true

require "test_helper"

# Stage 2 of the code-first registry: availability evaluated at the MCP
# serving boundary — tools/list hides unavailable tools, tools/call returns
# an actionable in-band error for entitled-but-disconnected tools and an
# opaque method_not_found for anything outside the session's entitlement.
class ActionMcpToolAvailabilityTest < ActiveSupport::TestCase
  class StubToolsHandler
    include ActionMCP::Server::Tools

    attr_reader :error_calls, :response_calls

    def initialize
      @error_calls = []
      @response_calls = []
    end

    def send_jsonrpc_error(request_id, code, message, data = nil)
      @error_calls << { request_id: request_id, code: code, message: message, data: data }
    end

    def send_jsonrpc_response(request_id, result: nil, error: nil)
      @response_calls << { request_id: request_id, result: result, error: error }
    end
  end

  setup do
    @user = create(:user, :with_company)
    @company = @user.company
    @project = create(:project, owner: @user, company: @company)
    @session = create(:terminal_session, user: @user, project: @project, session_type: "agent_session")
    ActionMCP::Current.terminal_session = @session
    @handler = StubToolsHandler.new
  end

  teardown do
    ActionMCP::Current.reset
  end

  def listed_tool_names
    @handler.response_calls.first[:result][:tools].map { |t| t["name"] }
  end

  def attach_platform_tool(name)
    Tool.shadow_for(Tools::Registry.fetch(name)).tap { |row| @session.tools << row }
  end

  test "tools/list hides an integration-gated tool until the integration is active" do
    attach_platform_tool("slack_post_message")
    attach_platform_tool("board_list_tasks")

    @handler.send_tools_list("req-1")
    assert_equal %w[board_list_tasks], listed_tool_names

    create(:integration, company: @company, project: @project, provider: :slack,
                         status: :active, connected_by: @user)
    @handler.response_calls.clear
    @handler.send_tools_list("req-2")
    assert_equal %w[board_list_tasks slack_post_message], listed_tool_names
  end

  test "tools/list returns deterministically ordered names with registry tags in _meta" do
    attach_platform_tool("mark_sub_step")
    attach_platform_tool("board_list_tasks")

    @handler.send_tools_list("req-1")

    tools = @handler.response_calls.first[:result][:tools]
    assert_equal tools.map { |t| t["name"] }.sort, tools.map { |t| t["name"] }
    board = tools.find { |t| t["name"] == "board_list_tasks" }
    assert_equal [ "board" ], board.dig("_meta", "ai.aixle/tags")
  end

  test "tools/list serializes from the definition even when the shadow row is stale" do
    row = attach_platform_tool("read_tool_result")
    row.update_columns(description: "STALE", input_schema: { "type" => "object" })

    @handler.send_tools_list("req-1")

    serialized = @handler.response_calls.first[:result][:tools].find { |t| t["name"] == "read_tool_result" }
    definition = Tools::Registry.fetch("read_tool_result")
    assert_equal definition.description, serialized["description"]
    assert_equal definition.input_schema, serialized["inputSchema"]
  end

  test "tools/call on an entitled-but-disconnected tool returns an actionable error, not method_not_found" do
    attach_platform_tool("slack_post_message")

    @handler.send_tools_call("req-1", "slack_post_message", { "text" => "hi" })

    assert_empty @handler.error_calls
    content = @handler.response_calls.first[:result][:content]
    text = content.map { |c| c[:text] }.join("\n")
    assert_match(/slack integration is not connected/i, text)
    assert_match(/Project Settings/, text)
  end

  test "tools/call on a tool outside the session stays an opaque method_not_found" do
    @handler.send_tools_call("req-1", "slack_post_message", {})

    assert_empty @handler.response_calls
    assert_equal :method_not_found, @handler.error_calls.first[:code]
  end

  test "tools/call executes normally once the integration is connected" do
    attach_platform_tool("list_sub_steps")

    @handler.send_tools_call("req-1", "list_sub_steps", {})

    # list_sub_steps has no integration requirement; it executes (and errors
    # about missing workflow context — which proves it reached the handler).
    assert_empty @handler.error_calls
    text = @handler.response_calls.first[:result][:content].map { |c| c[:text] }.join("\n")
    assert_match(/workflow context/i, text)
  end
end
