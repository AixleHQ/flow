# frozen_string_literal: true

require "test_helper"

class InternalTools::ReadToolResultTest < ActiveSupport::TestCase
  setup do
    @tool = create(:tool, :internal, name: "read_tool_result",
      display_name: "Read Tool Result")
    @session = create(:terminal_session, :agent_session, user: create(:user, :with_company))
  end

  test "returns serialized JSON for completed tool result" do
    tr = create(:tool_result, tool: @tool, terminal_session: @session)
    tr.complete!(exit_code: 0, stdout: '{"issues": 3}', stderr: "", duration_ms: 100)

    handler = InternalTools::ReadToolResult.new(
      params: { tool_result_id: tr.execution_id },
      session: @session
    )
    result = handler.execute

    assert_equal 0, result[:exit_code]

    parsed = JSON.parse(result[:stdout])
    assert_equal tr.execution_id, parsed["execution_id"]
    assert_equal "completed", parsed["state"]
    assert_equal 0, parsed["exit_code"]
    assert parsed["stdout_url"].present?
    assert parsed["result_data_url"].present?
  end

  test "returns processing state for unfinished tool result" do
    tr = create(:tool_result, tool: @tool, terminal_session: @session)

    handler = InternalTools::ReadToolResult.new(
      params: { tool_result_id: tr.execution_id },
      session: @session
    )
    result = handler.execute

    assert_equal 0, result[:exit_code]
    parsed = JSON.parse(result[:stdout])
    assert_equal "processing", parsed["state"]
    assert_nil parsed["stdout_url"]
  end

  test "returns error for nonexistent tool result" do
    handler = InternalTools::ReadToolResult.new(
      params: { tool_result_id: "tr-nonexistent" },
      session: @session
    )
    result = handler.execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not found"
  end

  test "returns failed state with error field" do
    tr = create(:tool_result, tool: @tool, terminal_session: @session)
    tr.complete!(exit_code: 1, stdout: "", stderr: "crash", duration_ms: 500,
                 error: "Timed out after 600s")

    handler = InternalTools::ReadToolResult.new(
      params: { tool_result_id: tr.execution_id },
      session: @session
    )
    result = handler.execute

    parsed = JSON.parse(result[:stdout])
    assert_equal "failed", parsed["state"]
    assert_equal "Timed out after 600s", parsed["error"]
  end
  test "does not read a result that belongs to another session" do
    other = create(:tool_result, tool: @tool, terminal_session: create(:terminal_session, :agent_session, user: create(:user, :with_company)))
    other.complete!(exit_code: 0, stdout: "theirs", stderr: "", duration_ms: 10)

    result = InternalTools::ReadToolResult.new(params: { tool_result_id: other.execution_id }, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not found"
  end
end
