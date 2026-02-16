# frozen_string_literal: true

require "test_helper"

module ContainerStrategies
  class ToolExecutionStrategyTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @tool = create(:tool, :with_files, scope: @company, docker_image: "alpine:latest", command: "echo 'hello'")

      @api_key = create(:config_item, name: "API_KEY", value: "secret123", scope: @company)
      @tool.update!(required_config_items: [ "API_KEY" ])

      @runtime_mock = mock("runtime")
      ContainerRuntime.stubs(:build).returns(@runtime_mock)

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

      env_vars = strategy.build_env_vars
      # Only project vars if project is present, none otherwise
      assert_empty env_vars
    end

    test "injects MCP parameters as env vars" do
      @tool.update!(required_config_items: [])

      strategy = ToolExecutionStrategy.new(
        tool: @tool,
        parameters: { "SLACK_RANGE" => "30d", "custom_param" => "value" }
      )

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "SLACK_RANGE=30d"
      assert_includes env_vars, "CUSTOM_PARAM=value"
    end

    test "config items take precedence over parameters" do
      strategy = ToolExecutionStrategy.new(
        tool: @tool,
        parameters: { "API_KEY" => "from_param" }
      )

      env_vars = strategy.build_env_vars

      # Config item value wins over parameter
      assert_includes env_vars, "API_KEY=secret123"
      refute_includes env_vars, "API_KEY=from_param"
    end

    test "injects project context as env vars" do
      strategy = ToolExecutionStrategy.new(tool: @tool, project: @project)
      @tool.update!(required_config_items: [])

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "PALAD_PROJECT_ID=#{@project.id}"
      assert_includes env_vars, "PALAD_PROJECT_NAME=#{@project.name}"
    end

    test "does not inject project vars when project is nil" do
      strategy = ToolExecutionStrategy.new(tool: @tool, project: nil)
      @tool.update!(required_config_items: [])

      env_vars = strategy.build_env_vars

      refute env_vars.any? { |v| v.start_with?("PALAD_PROJECT") }
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

    test "builds cmd with file setup and tool command when tool has files" do
      strategy = ToolExecutionStrategy.new(tool: @tool)
      cmd = strategy.build_cmd

      assert_equal "/bin/sh", cmd[0]
      assert_equal "-c", cmd[1]
      # CMD should contain mkdir + base64 decode for each file, then the tool command
      @tool.tool_files.each do |tf|
        assert_includes cmd[2], "mkdir -p"
        assert_includes cmd[2], "base64 -d"
      end
      assert cmd[2].end_with?("echo 'hello'"), "CMD should end with tool command"
    end

    test "builds cmd without file setup when no tool files" do
      @tool.tool_files.destroy_all

      strategy = ToolExecutionStrategy.new(tool: @tool.reload)

      assert_equal [ "/bin/sh", "-c", "echo 'hello'" ], strategy.build_cmd
    end

    test "builds cmd with parameter substitution" do
      @tool.tool_files.destroy_all
      @tool.update!(command: "python {{script}} --env={{env}}")

      strategy = ToolExecutionStrategy.new(
        tool: @tool.reload,
        parameters: { script: "main.py", env: "production" }
      )

      assert_equal [ "/bin/sh", "-c", "python main.py --env=production" ], strategy.build_cmd
    end

    test "builds cmd with /bin/sh when no command specified" do
      @tool.tool_files.destroy_all
      @tool.update!(command: nil)

      strategy = ToolExecutionStrategy.new(tool: @tool.reload)

      assert_equal [ "/bin/sh", "-c", "/bin/sh" ], strategy.build_cmd
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

    # == Start Tests (skip health check) ==

    test "start skips health check for tool containers" do
      strategy = ToolExecutionStrategy.new(tool: @tool)
      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123")

      @runtime_mock.expects(:start_container).with(container_mock).returns(container_mock)
      @runtime_mock.expects(:wait_for_ready).never

      context = { container: container_mock }
      strategy.start(context)

      assert_equal container_mock, context[:container]
      assert_equal "abc123", context[:container_id]
    end

    # == Exec Tests (wait + logs) ==

    test "exec waits for container and collects logs" do
      strategy = ToolExecutionStrategy.new(tool: @tool)
      container_mock = mock("container")

      @runtime_mock.expects(:wait_container).with(container_mock).returns({ "StatusCode" => 0 })
      @runtime_mock.expects(:container_logs).with(container_mock).returns({
        stdout: "hello\n",
        stderr: ""
      })

      context = { container: container_mock }
      strategy.exec(context)

      assert_equal 0, context[:result][:exit_code]
      assert_equal "hello\n", context[:result][:stdout]
      assert_equal "", context[:result][:stderr]
      assert_equal false, context[:result][:timed_out]
      assert context[:result][:duration_ms] >= 0
    end

    test "exec handles non-zero exit code" do
      strategy = ToolExecutionStrategy.new(tool: @tool)
      container_mock = mock("container")

      @runtime_mock.expects(:wait_container).with(container_mock).returns({ "StatusCode" => 1 })
      @runtime_mock.expects(:container_logs).with(container_mock).returns({
        stdout: "",
        stderr: "error occurred"
      })

      context = { container: container_mock }
      strategy.exec(context)

      assert_equal 1, context[:result][:exit_code]
      assert_equal "error occurred", context[:result][:stderr]
    end

    test "exec handles timeout by killing container and collecting partial logs" do
      strategy = ToolExecutionStrategy.new(tool: @tool)
      container_mock = mock("container")

      @runtime_mock.expects(:wait_container).with(container_mock).raises(Timeout::Error)
      container_mock.expects(:kill)
      @runtime_mock.expects(:container_logs).with(container_mock).returns({
        stdout: "partial output",
        stderr: "partial err"
      })

      context = { container: container_mock }
      strategy.exec(context)

      assert_equal 124, context[:result][:exit_code]
      assert_equal true, context[:result][:timed_out]
      assert_equal "partial output", context[:result][:stdout]
      assert_includes context[:result][:stderr], "timed out"
      assert_includes context[:result][:stderr], "partial err"
    end

    test "exec handles timeout when kill and logs fail" do
      strategy = ToolExecutionStrategy.new(tool: @tool)
      container_mock = mock("container")

      @runtime_mock.expects(:wait_container).raises(Timeout::Error)
      container_mock.expects(:kill).raises(StandardError.new("already dead"))
      @runtime_mock.expects(:container_logs).raises(StandardError.new("no logs"))

      context = { container: container_mock }
      strategy.exec(context)

      assert_equal 124, context[:result][:exit_code]
      assert_equal true, context[:result][:timed_out]
    end

    # == Output Truncation Tests ==

    test "truncates large output" do
      strategy = ToolExecutionStrategy.new(tool: @tool)
      large_output = "x" * (15 * 1024 * 1024)

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

    # == Full before_create Flow Test ==

    test "before_create populates context correctly" do
      strategy = ToolExecutionStrategy.new(tool: @tool, project: @project)
      context = {}

      strategy.before_create(context)

      assert_equal "alpine:latest", context[:image]
      assert_includes context[:env_vars], "API_KEY=secret123"
      assert_includes context[:env_vars], "PALAD_PROJECT_ID=#{@project.id}"
      assert_includes context[:env_vars], "PALAD_PROJECT_NAME=#{@project.name}"
      assert_equal "tool_execution", context[:labels]["palad.type"]
      # CMD includes file setup when tool has files
      assert_equal "/bin/sh", context[:cmd][0]
      assert_equal "-c", context[:cmd][1]
      assert context[:cmd][2].end_with?("echo 'hello'")
      assert_equal "/workspace", context[:working_dir]
      assert context[:host_config]["Memory"] > 0
    end

    # == before_cleanup Tests (archive-based) ==

    test "before_cleanup collects output files via read_file" do
      @tool.define_singleton_method(:output_paths) { [ "/output/result.json" ] }

      container_mock = mock("container")
      strategy = ToolExecutionStrategy.new(tool: @tool)

      @runtime_mock.expects(:read_file).with(container_mock, "/output/result.json").returns('{"result": "ok"}')

      context = { container: container_mock }
      strategy.before_cleanup(context)

      assert context[:result][:output_files].key?("/output/result.json")
      assert_equal '{"result": "ok"}', context[:result][:output_files]["/output/result.json"]
    end

    test "before_cleanup skips when tool has no output_paths" do
      strategy = ToolExecutionStrategy.new(tool: @tool)

      @runtime_mock.expects(:read_file).never

      container_mock = mock("container")
      context = { container: container_mock }
      strategy.before_cleanup(context)

      assert true
    end

    test "before_cleanup handles file read errors gracefully" do
      @tool.define_singleton_method(:output_paths) { [ "/missing/file" ] }

      container_mock = mock("container")
      strategy = ToolExecutionStrategy.new(tool: @tool)

      @runtime_mock.expects(:read_file).with(container_mock, "/missing/file").raises(StandardError.new("Not found"))

      context = { container: container_mock }
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
  end
end
