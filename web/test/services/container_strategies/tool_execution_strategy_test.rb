# frozen_string_literal: true

require "test_helper"

module ContainerStrategies
  class ToolExecutionStrategyTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @tool = create(:tool, :with_files, scope: @company, docker_image: "alpine:latest", command: "echo 'hello'")

      # Create config items
      @api_key = create(:config_item, name: "API_KEY", value: "secret123", scope: @company)
      @tool.update!(required_config_items: [ "API_KEY" ])

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
    end

    # == Initialization Tests ==

    test "raises error for internal tools" do
      internal_tool = create(:tool, :internal, name: "internal_tool")

      strategy = ToolExecutionStrategy.new(tool: internal_tool)
      context = {}

      assert_raises(ArgumentError) do
        strategy.before_create(context)
      end
    end

    test "raises error for tools without docker_image" do
      @tool.update_column(:docker_image, nil)

      strategy = ToolExecutionStrategy.new(tool: @tool.reload)
      context = {}

      assert_raises(ArgumentError) do
        strategy.before_create(context)
      end
    end

    # == Image Resolution Tests ==

    test "resolves image from tool" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      assert_equal "alpine:latest", strategy.resolve_image
    end

    # == Environment Variables Tests ==

    test "builds env vars from config items" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "API_KEY=secret123"
    end

    test "resolves config items with project override" do
      create(:config_item, name: "API_KEY", value: "project_secret", scope: @project)

      strategy = ToolExecutionStrategy.new(tool: @tool, project: @project)

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "API_KEY=project_secret"
    end

    test "returns empty env vars when no config items required" do
      @tool.update!(required_config_items: [])

      strategy = ToolExecutionStrategy.new(tool: @tool)

      assert_empty strategy.build_env_vars
    end

    # == Labels Tests ==

    test "builds labels with tool info" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      labels = strategy.build_labels

      assert_equal "tool_execution", labels["palad.type"]
      assert_equal @tool.id.to_s, labels["palad.tool_id"]
      assert_equal @tool.name, labels["palad.tool_name"]
    end

    # == Host Config Tests ==

    test "builds host config with resource limits" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      host_config = strategy.build_host_config

      assert_equal 1024 * 1024 * 1024, host_config["Memory"]
      assert_equal 1024 * 1024 * 1024, host_config["MemorySwap"]
      assert_equal 100_000, host_config["CpuPeriod"]
      assert_equal 50_000, host_config["CpuQuota"]
    end

    # == Command Tests ==

    test "builds cmd with sleep for file injection" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      assert_equal [ "sleep", "infinity" ], strategy.build_cmd
    end

    test "builds working directory" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      assert_equal "/workspace", strategy.build_working_dir
    end

    # == Timeout Tests ==

    test "returns default timeout for exec phase" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      assert_equal 300, strategy.timeout_for(:exec)
    end

    test "respects custom timeout" do
      strategy = ToolExecutionStrategy.new(tool: @tool, timeout: 600)

      assert_equal 600, strategy.timeout_for(:exec)
    end

    test "caps timeout at max value" do
      strategy = ToolExecutionStrategy.new(tool: @tool, timeout: 9999)

      assert_equal 1800, strategy.timeout_for(:exec)
    end

    test "returns nil for non-exec phases" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      assert_nil strategy.timeout_for(:before_create)
      assert_nil strategy.timeout_for(:cleanup)
    end

    # == File Injection Tests ==

    test "before_exec injects tool files" do
      container_mock = mock("container")

      # Tool has 2 files (from :with_files trait), both in /workspace
      # Expect mkdir and file write for each file (2 files = 4 calls)
      container_mock.expects(:exec).with([ "mkdir", "-p", "/workspace" ]).twice
      container_mock.expects(:exec).with do |args|
        args[0] == "/bin/sh" && args[1] == "-c" && args[2].include?("base64 -d")
      end.twice

      strategy = ToolExecutionStrategy.new(tool: @tool)
      context = { container: container_mock }

      strategy.before_exec(context)

      assert true # Expectations verified by mocha
    end

    test "before_exec skips when no tool files" do
      @tool.tool_files.destroy_all

      container_mock = mock("container")
      container_mock.expects(:exec).never

      strategy = ToolExecutionStrategy.new(tool: @tool.reload)
      context = { container: container_mock }

      strategy.before_exec(context)
    end

    # == Command Building Tests ==

    test "builds command with parameter substitution" do
      @tool.update!(command: "python {{script}} --env={{env}}")

      strategy = ToolExecutionStrategy.new(tool: @tool, parameters: { script: "main.py", env: "production" })
      command = strategy.send(:build_command, @tool, { script: "main.py", env: "production" })

      assert_equal "python main.py --env=production", command
    end

    test "uses /bin/sh when no command specified" do
      @tool.update!(command: nil)

      strategy = ToolExecutionStrategy.new(tool: @tool)
      command = strategy.send(:build_command, @tool, {})

      assert_equal "/bin/sh", command
    end

    # == Exec Phase Tests ==

    test "exec sets result in context" do
      container_mock = mock("container")
      container_mock.expects(:exec).with(
        [ "/bin/sh", "-c", "echo 'hello'" ],
        stdout: true,
        stderr: true
      ).returns([ [ "hello\n" ], [], 0 ])

      strategy = ToolExecutionStrategy.new(tool: @tool)
      context = { container: container_mock }

      strategy.exec(context)

      assert_equal 0, context[:result][:exit_code]
      assert_equal "hello\n", context[:result][:stdout]
      assert_equal "", context[:result][:stderr]
      assert_equal false, context[:result][:timed_out]
      assert context[:result][:duration_ms] >= 0
    end

    # == Output Truncation Tests ==

    test "truncates large output" do
      strategy = ToolExecutionStrategy.new(tool: @tool)
      large_output = "x" * (15 * 1024 * 1024) # 15MB (exceeds 10MB limit)

      truncated = strategy.send(:truncate_output, large_output)

      assert truncated.bytesize <= ToolExecutionStrategy::MAX_OUTPUT_SIZE + 100
      assert truncated.include?("truncated")
    end

    test "does not truncate small output" do
      strategy = ToolExecutionStrategy.new(tool: @tool)
      small_output = "hello world"

      result = strategy.send(:truncate_output, small_output)

      assert_equal "hello world", result
    end

    test "handles nil output" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      assert_equal "", strategy.send(:truncate_output, nil)
    end

    # == Timeout Handling Tests ==

    test "handles execution timeout" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      container_mock = mock("container")
      container_mock.expects(:kill)

      context = { container: container_mock }
      start_time = Time.current - 10.seconds

      strategy.send(:handle_execution_timeout, context, start_time, 5)

      assert_equal 124, context[:result][:exit_code]
      assert_equal true, context[:result][:timed_out]
      assert context[:result][:stderr].include?("timed out")
    end

    # == Full before_create Flow Test ==

    test "before_create populates context correctly" do
      strategy = ToolExecutionStrategy.new(tool: @tool, project: @project)
      context = {}

      strategy.before_create(context)

      assert_equal "alpine:latest", context[:image]
      assert_includes context[:env_vars], "API_KEY=secret123"
      assert_equal "tool_execution", context[:labels]["palad.type"]
      assert_equal [ "sleep", "infinity" ], context[:cmd]
      assert_equal "/workspace", context[:working_dir]
      assert context[:host_config]["Memory"] > 0
    end

    # == before_cleanup Tests ==

    test "before_cleanup collects output files when tool has output_paths" do
      @tool.define_singleton_method(:output_paths) { [ "/output/result.json" ] }

      container_mock = mock("container")
      strategy = ToolExecutionStrategy.new(tool: @tool)
      strategy.stubs(:read_file_from_container).with(container_mock, "/output/result.json").returns('{"result": "ok"}')

      context = { container: container_mock }
      strategy.before_cleanup(context)

      assert context[:result][:output_files].key?("/output/result.json")
      assert_equal '{"result": "ok"}', context[:result][:output_files]["/output/result.json"]
    end

    test "before_cleanup skips when tool has no output_paths" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      container_mock = mock("container")
      context = { container: container_mock }
      strategy.before_cleanup(context)

      # Should complete without errors
      assert true
    end

    test "before_cleanup handles file read errors gracefully" do
      @tool.define_singleton_method(:output_paths) { [ "/missing/file" ] }

      container_mock = mock("container")
      strategy = ToolExecutionStrategy.new(tool: @tool)
      strategy.stubs(:read_file_from_container).raises(StandardError.new("File not found"))

      context = { container: container_mock }
      # Should not raise
      strategy.before_cleanup(context)

      assert context[:result][:output_files].empty?
    end

    # == Config Item Resolution Tests ==

    test "skips missing config items" do
      @tool.update!(required_config_items: [ "MISSING_KEY" ])
      strategy = ToolExecutionStrategy.new(tool: @tool)

      env_vars = strategy.build_env_vars

      assert_empty env_vars
    end

    test "resolves config from company when project is nil" do
      strategy = ToolExecutionStrategy.new(tool: @tool, project: nil)

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "API_KEY=secret123"
    end

    # == Timeout Handling with Kill Error ==

    test "handles container kill errors during timeout" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      container_mock = mock("container")
      container_mock.stubs(:kill).raises(StandardError.new("Already dead"))

      context = { container: container_mock }
      start_time = Time.current

      # Should not raise
      strategy.send(:handle_execution_timeout, context, start_time, 5)

      assert_equal 124, context[:result][:exit_code]
    end
  end
end
