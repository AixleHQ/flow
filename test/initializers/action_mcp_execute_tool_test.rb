# frozen_string_literal: true

require "test_helper"

class ActionMcpExecuteToolTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)

    @session = Object.new
    @session.define_singleton_method(:project) { @project }
    @session.define_singleton_method(:step_run) { nil }
  end

  test "app tool returns direct result" do
    tool = create(:tool, :internal, name: "mcp_test",
      display_name: "MCP Test", execution_mode: :app)

    stub_handler = Class.new(InternalTools::Base) do
      def execute
        success("direct result")
      end
    end
    InternalTools.const_set(:MCPTest, stub_handler)

    result = tool.execute(parameters: {}, session: @session)
    assert_equal 0, result[:exit_code]
    assert_equal "direct result", result[:stdout]
  ensure
    InternalTools.send(:remove_const, :MCPTest) if InternalTools.const_defined?(:MCPTest)
  end

  test "container tool creates ToolResult and returns execution_id" do
    tool = create(:tool, scope: @company, docker_image: "alpine:latest",
      command: "echo hi", execution_mode: :container)

    mock_strategy = mock("strategy")
    mock_strategy.stubs(:build_manifest).returns({})
    ContainerStrategies::CustomToolStrategy.stubs(:new).returns(mock_strategy)
    TemporalService.stubs(:start_workflow).returns("wf-123")

    tool_result = ToolResult.create!(
      tool: tool,
      terminal_session: nil,
      execution_id: ToolResult.generate_id,
      state: "processing"
    )

    result = { exit_code: 0, stdout: tool_result.execution_id }

    assert_match(/\Atr-/, result[:stdout])
    assert_equal 0, result[:exit_code]
  end

  test "ToolResult.generate_id is used for execution_id" do
    id = ToolResult.generate_id
    assert_match(/\Atr-[a-f0-9]{24}\z/, id)
  end
end
