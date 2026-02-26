# frozen_string_literal: true

require "test_helper"

class ToolExecuteRoutingTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = Object.new
    @session.define_singleton_method(:project) { @project }
    @session.define_singleton_method(:step_run) { nil }
  end

  test "app-mode tool routes to InternalToolExecutor" do
    tool = create(:tool, :internal, name: "routing_test",
      display_name: "Routing Test", input_schema: {}, execution_mode: :app)

    stub_handler = Class.new(InternalTools::Base) do
      def execute
        success("routed to internal")
      end
    end
    InternalTools.const_set(:RoutingTest, stub_handler)

    result = tool.execute(parameters: {}, session: @session)

    assert_equal 0, result[:exit_code]
    assert_equal "routed to internal", result[:stdout]
  ensure
    InternalTools.send(:remove_const, :RoutingTest) if InternalTools.const_defined?(:RoutingTest)
  end

  test "container-mode tool routes to Temporal via start_container_execution" do
    tool = create(:tool, scope: @company, kind: :custom,
      docker_image: "alpine:latest", command: "echo hi", execution_mode: :container)

    mock_strategy = mock("strategy")
    mock_strategy.stubs(:build_manifest).returns({})

    ContainerStrategies::CustomToolStrategy.stubs(:new).returns(mock_strategy)
    TemporalService.stubs(:start_workflow).returns("wf-id-123")

    result = tool.execute(parameters: {}, project: @project)

    assert_equal "wf-id-123", result
  end

  test "default execution_mode is container" do
    tool = build(:tool, scope: @company)
    assert_equal "container", tool.execution_mode.to_s
  end

  test "internal tool with execution_mode app does not hit container path" do
    tool = create(:tool, :internal, name: "app_only_test",
      display_name: "App Only", input_schema: {}, execution_mode: :app)

    stub_handler = Class.new(InternalTools::Base) do
      def execute
        success("app mode works")
      end
    end
    InternalTools.const_set(:AppOnlyTest, stub_handler)

    TemporalService.expects(:start_workflow).never

    result = tool.execute(parameters: {}, session: @session)
    assert_equal 0, result[:exit_code]
  ensure
    InternalTools.send(:remove_const, :AppOnlyTest) if InternalTools.const_defined?(:AppOnlyTest)
  end

  test "container tool passes tool_result_id to strategy" do
    tool = create(:tool, scope: @company, kind: :custom,
      docker_image: "alpine:latest", command: "echo hi", execution_mode: :container)

    mock_strategy = mock("strategy")
    mock_strategy.stubs(:build_manifest).returns({})

    ContainerStrategies::CustomToolStrategy.stubs(:new).returns(mock_strategy)
    TemporalService.stubs(:start_workflow).with do |_workflow, payload, **_opts|
      payload[:tool_result_id] == 42
    end.returns("wf-id-456")

    result = tool.execute(parameters: {}, project: @project, tool_result_id: 42)

    assert_equal "wf-id-456", result
  end
end
