# frozen_string_literal: true

require "test_helper"

class ContainerStrategies::InternalToolStrategyTest < ActiveSupport::TestCase
  setup do
    @registry_backup = ContainerStrategies::InternalToolStrategy.registry.dup

    ContainerStrategies::InternalToolStrategy.define :test_tool do
      image "test-image:latest"
      timeout 120
      memory 512.megabytes
      cpu_quota 25_000
      working_dir "/app"

      cmd { |input| [ "run", "--format", input[:format] || "json" ] }
      env { |input| { "REPO_PATH" => input[:repo_path] || "/tmp" } }
      binds { |input| [ "#{input[:repo_path] || '/tmp'}:/app:ro" ] }

      prepare { |input|
        input.merge(repo_path: "/repos/test")
      }
    end

    ContainerStrategies::InternalToolStrategy.define :docker_tool do
      image "docker-tool:1.0"
      docker_socket!
      output_files [ "/output/report.json" ]
    end
  end

  teardown do
    ContainerStrategies::InternalToolStrategy.instance_variable_set(:@registry, @registry_backup)
  end

  test "define registers definition in registry" do
    assert ContainerStrategies::InternalToolStrategy.registry.key?("test_tool")
    defn = ContainerStrategies::InternalToolStrategy.registry["test_tool"]
    assert_equal :test_tool, defn.name
    assert_equal "test-image:latest", defn.opts[:image]
  end

  test "build_for raises for unknown definition" do
    error = assert_raises(ArgumentError) do
      ContainerStrategies::InternalToolStrategy.build_for(
        :nonexistent, params: {}, session: nil, tool_result_id: 1
      )
    end
    assert_match(/No internal tool definition/, error.message)
  end

  test "build_for runs prepare block and merges results" do
    strategy = ContainerStrategies::InternalToolStrategy.build_for(
      :test_tool, params: { format: "text" }, session: nil, tool_result_id: 1
    )
    assert_equal "/repos/test", strategy.input[:repo_path]
    assert_equal "text", strategy.input[:format]
  end

  test "resolve_image from definition" do
    strategy = build_test_strategy
    assert_equal "test-image:latest", strategy.resolve_image
  end

  test "build_cmd with callable block" do
    strategy = build_test_strategy(format: "csv")
    cmd = strategy.build_cmd
    assert_equal [ "run", "--format", "csv" ], cmd
  end

  test "build_env_vars from callable block" do
    strategy = build_test_strategy
    env = strategy.build_env_vars
    assert_includes env, "REPO_PATH=/repos/test"
  end

  test "build_labels includes internal_tool type" do
    strategy = build_test_strategy
    labels = strategy.build_labels
    assert_equal "internal_tool", labels["aixle.type"]
    assert_equal "test_tool", labels["aixle.tool"]
  end

  test "build_host_config with docker_socket mounts docker.sock" do
    strategy = ContainerStrategies::InternalToolStrategy.build_for(
      :docker_tool, params: {}, session: nil, tool_result_id: 1
    )
    hc = strategy.build_host_config
    assert hc["Binds"].any? { |b| b.include?("docker.sock") }
  end

  test "build_host_config without docker_socket has no socket bind" do
    strategy = build_test_strategy
    hc = strategy.build_host_config
    binds = hc["Binds"] || []
    assert_not binds.any? { |b| b.include?("docker.sock") }
  end

  test "build_host_config uses definition memory and cpu" do
    strategy = build_test_strategy
    hc = strategy.build_host_config
    assert_equal 512.megabytes, hc["Memory"]
    assert_equal 25_000, hc["CpuQuota"]
  end

  test "definition output_files accessible" do
    defn = ContainerStrategies::InternalToolStrategy.registry["docker_tool"]
    assert_equal [ "/output/report.json" ], defn.opts[:output_files]
  end

  private

  def build_test_strategy(**params)
    ContainerStrategies::InternalToolStrategy.build_for(
      :test_tool, params: params, session: nil, tool_result_id: 1
    )
  end
end
