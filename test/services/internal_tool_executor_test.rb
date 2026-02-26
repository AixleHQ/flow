# frozen_string_literal: true

require "test_helper"

class InternalToolExecutorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @session = Object.new
    @session.define_singleton_method(:project) { nil }
    @session.define_singleton_method(:step_run) { nil }
  end

  test "executes handler resolved by tool name" do
    tool = create(:tool, :internal, name: "echo_test",
      display_name: "Echo Test", input_schema: {})

    # Create a handler dynamically for test
    stub_handler = Class.new(InternalTools::Base) do
      def execute
        success("echo: #{params[:message]}")
      end
    end
    InternalTools.const_set(:EchoTest, stub_handler)

    result = InternalToolExecutor.execute(tool, { message: "hello" }, @session)

    assert_equal 0, result[:exit_code]
    assert_equal "echo: hello", result[:stdout]
  ensure
    InternalTools.send(:remove_const, :EchoTest) if InternalTools.const_defined?(:EchoTest)
  end

  test "returns error when handler class not found" do
    tool = create(:tool, :internal, name: "nonexistent_tool",
      display_name: "Missing", input_schema: {})

    result = InternalToolExecutor.execute(tool, {}, @session)

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "No handler found"
    assert_includes result[:stderr], "nonexistent_tool"
  end

  test "validates required params from input_schema" do
    tool = create(:tool, :internal, name: "validated_tool",
      display_name: "Validated", input_schema: {
        "type" => "object",
        "properties" => { "id" => { "type" => "integer" } },
        "required" => ["id"]
      })

    result = InternalToolExecutor.execute(tool, {}, @session)

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Missing required parameters: id"
  end

  test "skips validation when no input_schema" do
    tool = create(:tool, :internal, name: "no_schema_tool",
      display_name: "No Schema", input_schema: nil)

    stub_handler = Class.new(InternalTools::Base) do
      def execute
        success("ok")
      end
    end
    InternalTools.const_set(:NoSchemaTool, stub_handler)

    result = InternalToolExecutor.execute(tool, {}, @session)
    assert_equal 0, result[:exit_code]
  ensure
    InternalTools.send(:remove_const, :NoSchemaTool) if InternalTools.const_defined?(:NoSchemaTool)
  end

  test "catches handler errors and returns structured result" do
    tool = create(:tool, :internal, name: "failing_tool",
      display_name: "Failing", input_schema: {})

    stub_handler = Class.new(InternalTools::Base) do
      def execute
        raise "something went wrong"
      end
    end
    InternalTools.const_set(:FailingTool, stub_handler)

    result = InternalToolExecutor.execute(tool, {}, @session)

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "something went wrong"
  ensure
    InternalTools.send(:remove_const, :FailingTool) if InternalTools.const_defined?(:FailingTool)
  end

  test "catches WorkflowContextError specifically" do
    tool = create(:tool, :internal, name: "workflow_tool",
      display_name: "Workflow Tool", input_schema: {})

    stub_handler = Class.new(InternalTools::Base) do
      def execute
        require_workflow_context!
      end
    end
    InternalTools.const_set(:WorkflowTool, stub_handler)

    result = InternalToolExecutor.execute(tool, {}, @session)

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "workflow context"
  ensure
    InternalTools.send(:remove_const, :WorkflowTool) if InternalTools.const_defined?(:WorkflowTool)
  end
end
