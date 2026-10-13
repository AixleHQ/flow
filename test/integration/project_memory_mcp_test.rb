# frozen_string_literal: true

require "test_helper"

class ProjectMemoryMcpTest < ActionDispatch::IntegrationTest
  setup do
    @project = create(:project, :standalone)
    @session = create(:terminal_session, :agent_session, :running, project: @project, user: @project.owner)
    Tools::Reconciler.run!
  end

  test "project memory tools are absent by default" do
    names = rpc("tools/list").dig("result", "tools").pluck("name")
    assert_empty names.grep(/\Amemory_/)
  end

  test "enabled project exposes only scoped memory tools and captures pending findings" do
    @project.update!(memory_enabled: true)
    Engram::Client.stubs(:configured?).returns(true)
    Engram::Client.stubs(:build).returns(FakeEngramClient.new)
    tools = rpc("tools/list").dig("result", "tools")
    assert_equal %w[memory_capture memory_get memory_search], tools.pluck("name").grep(/\Amemory_/).sort
    assert tools.select { |tool| tool["name"].start_with?("memory_") }
      .none? { |tool| tool.dig("inputSchema", "properties").key?("project_id") }

    body = rpc("tools/call", name: "memory_capture", arguments: {
      title: "Transaction convention", content: "Use explicit transactions", topic_key: "pattern/transactions", sources: "[]"
    })
    assert_not body.dig("result", "isError"), body.inspect
    memory = @project.project_memories.sole
    assert_equal "pending", memory.state
    assert_equal @session.id, memory.terminal_session_id
  end

  test "disabled session cannot use tools even when attached manually" do
    @project.update!(memory_enabled: true)
    Engram::Client.stubs(:configured?).returns(true)
    @session.update!(metadata: { "memory_disabled" => true })
    @session.tools << Tool.find_by!(name: "memory_capture")

    assert_empty rpc("tools/list").dig("result", "tools").pluck("name").grep(/\Amemory_/)
    rpc("tools/call", name: "memory_capture", arguments: { title: "No", content: "No", topic_key: "no", sources: "[]" })
    assert_equal 0, ProjectMemory.count
  end

  private

  def rpc(method, params = {})
    post "/action_mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "X-Session-Key" => @session.mcp_key }
    response.parsed_body
  end
end
