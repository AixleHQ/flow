# frozen_string_literal: true

require "test_helper"

module ContainerStrategies
  class BaseStrategyTest < ActiveSupport::TestCase
    class TestStrategy < BaseStrategy
      def resolve_image
        "test-image:latest"
      end

      def build_env_vars
        [ "FOO=bar", "BAZ=qux" ]
      end

      def build_labels
        { "test" => "true", "env" => "test" }
      end

      def before_create_container(**)
        {
          image: resolve_image,
          env_vars: build_env_vars,
          labels: build_labels,
          host_config: build_host_config
        }
      end

      def exec(container_id:, **)
        { result: { status: :success } }
      end
    end

    setup do
      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)

      @runtime_mock = mock("runtime")
      @runtime_mock.stubs(:container_identifier) { |container| container }
      ContainerRuntime.stubs(:build).returns(@runtime_mock)
    end

    test "accepts hash input" do
      strategy = TestStrategy.new(foo: "bar")
      assert_equal "bar", strategy.input[:foo]
    end

    test "converts hash to indifferent access" do
      strategy = TestStrategy.new("foo" => "bar")
      assert_equal "bar", strategy.input[:foo]
      assert_equal "bar", strategy.input["foo"]
    end

    test "before_create_container populates context with container config" do
      strategy = TestStrategy.new
      result = strategy.before_create_container

      assert_equal "test-image:latest", result[:image]
      assert_equal [ "FOO=bar", "BAZ=qux" ], result[:env_vars]
      assert_equal({ "test" => "true", "env" => "test" }, result[:labels])
      assert_equal Settings.docker.network, result[:host_config]["NetworkMode"]
    end

    test "create_container creates container via runtime" do
      strategy = TestStrategy.new

      @runtime_mock.expects(:create_container).with do |spec|
        spec[:image] == "test:latest" &&
          spec[:env_vars] == [ "A=1" ] &&
          spec[:labels] == { "x" => "y" } &&
          spec[:host_config] == { "NetworkMode" => "bridge" }
      end.returns("container-handle-123")

      result = strategy.create_container(
        image: "test:latest",
        env_vars: [ "A=1" ],
        labels: { "x" => "y" },
        host_config: { "NetworkMode" => "bridge" }
      )

      assert_equal "container-handle-123", result[:container_id]
    end

    test "create_container includes optional fields when present" do
      strategy = TestStrategy.new

      @runtime_mock.expects(:create_container).with do |spec|
        spec[:image] == "test:latest" &&
          spec[:cmd] == [ "/bin/sh", "-c", "echo hello" ] &&
          spec[:working_dir] == "/workspace" &&
          spec[:exposed_ports] == { "8080/tcp" => {} } &&
          spec[:container_name] == "test-container"
      end.returns("container-handle")

      strategy.create_container(
        image: "test:latest",
        env_vars: [],
        labels: {},
        host_config: {},
        cmd: [ "/bin/sh", "-c", "echo hello" ],
        working_dir: "/workspace",
        exposed_ports: { "8080/tcp" => {} },
        container_name: "test-container"
      )
    end

    test "create_container preserves namespace-aware runtime identifier" do
      strategy = TestStrategy.new
      handle = OpenStruct.new(namespace: "palad-user-4", pod_name: "terminal-abc")

      @runtime_mock.expects(:create_container).returns(handle)
      @runtime_mock.expects(:container_identifier).with(handle).returns("palad-user-4/terminal-abc")

      result = strategy.create_container(
        image: "test:latest",
        env_vars: [],
        labels: {},
        host_config: {}
      )

      assert_equal "palad-user-4/terminal-abc", result[:container_id]
    end

    test "start_container starts container and waits for readiness" do
      strategy = TestStrategy.new

      @runtime_mock.expects(:resolve_container).with("container-ref").returns("container-ref")
      @runtime_mock.expects(:start_container).with("container-ref").returns("container-ref")
      @runtime_mock.expects(:wait_for_ready).with("container-ref", [])

      strategy.start_container(container_id: "container-ref")
    end

    test "cleanup stops and removes container" do
      strategy = TestStrategy.new

      @runtime_mock.expects(:resolve_container).with("container-ref").returns("container-ref")
      @runtime_mock.expects(:stop_container).with("container-ref", 5)
      @runtime_mock.expects(:remove_container).with("container-ref")

      result = strategy.cleanup(container_id: "container-ref")
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup handles missing container gracefully" do
      strategy = TestStrategy.new

      result = strategy.cleanup(container_id: nil)
      assert_equal :skipped, result[:status]
    end

    test "cleanup handles stop failure" do
      strategy = TestStrategy.new

      @runtime_mock.expects(:resolve_container).with("container-ref").returns("container-ref")
      @runtime_mock.expects(:stop_container).raises(StandardError.new("stop failed"))
      @runtime_mock.expects(:remove_container).with("container-ref")

      result = strategy.cleanup(container_id: "container-ref")
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup returns failed when remove fails" do
      strategy = TestStrategy.new

      @runtime_mock.expects(:resolve_container).with("container-ref").returns("container-ref")
      @runtime_mock.expects(:stop_container).with("container-ref", 5)
      @runtime_mock.expects(:remove_container).raises(StandardError.new("remove failed"))

      result = strategy.cleanup(container_id: "container-ref")
      assert_equal :failed, result[:status]
      assert_equal "remove failed", result[:cleanup_error]
    end

    test "cleanup removes image when remove_image_after_cleanup? is true" do
      strategy = TestStrategy.new
      strategy.define_singleton_method(:remove_image_after_cleanup?) { true }

      @runtime_mock.expects(:resolve_container).with("container-ref").returns("container-ref")
      @runtime_mock.expects(:stop_container).with("container-ref", 5)
      @runtime_mock.expects(:remove_container).with("container-ref")
      @runtime_mock.expects(:remove_image).with("test-image:latest")

      result = strategy.cleanup(container_id: "container-ref", image: "test-image:latest")
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup does not remove image by default" do
      strategy = TestStrategy.new

      @runtime_mock.expects(:resolve_container).with("container-ref").returns("container-ref")
      @runtime_mock.expects(:stop_container).with("container-ref", 5)
      @runtime_mock.expects(:remove_container).with("container-ref")
      @runtime_mock.expects(:remove_image).never

      result = strategy.cleanup(container_id: "container-ref", image: "test-image:latest")
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup handles image removal error gracefully" do
      strategy = TestStrategy.new
      strategy.define_singleton_method(:remove_image_after_cleanup?) { true }

      @runtime_mock.stubs(:resolve_container).returns("container-ref")
      @runtime_mock.stubs(:stop_container)
      @runtime_mock.stubs(:remove_container)
      @runtime_mock.expects(:remove_image).with("busy-image:latest").raises(StandardError.new("image in use"))

      result = strategy.cleanup(container_id: "container-ref", image: "busy-image:latest")
      assert_includes [ :cleaned_up, :failed ], result[:status]
    end

    test "resolve_image raises NotImplementedError in base class" do
      strategy = BaseStrategy.new

      assert_raises(NotImplementedError) do
        strategy.resolve_image
      end
    end

    test "build_env_vars returns empty array by default" do
      strategy = BaseStrategy.new
      assert_equal [], strategy.build_env_vars
    end

    test "build_labels returns empty hash by default" do
      strategy = BaseStrategy.new
      assert_equal({}, strategy.build_labels)
    end

    test "build_host_config returns default network config" do
      strategy = BaseStrategy.new
      config = strategy.build_host_config

      assert_equal Settings.docker.network, config["NetworkMode"]
      assert_equal false, config["AutoRemove"]
    end

    test "build_exposed_ports returns nil by default" do
      strategy = BaseStrategy.new
      assert_nil strategy.build_exposed_ports
    end

    test "build_cmd returns nil by default" do
      strategy = BaseStrategy.new
      assert_nil strategy.build_cmd
    end

    test "build_working_dir returns nil by default" do
      strategy = BaseStrategy.new
      assert_nil strategy.build_working_dir
    end

    test "phase_config returns timeout by default" do
      strategy = BaseStrategy.new
      config = strategy.phase_config(:exec)
      assert_equal 300, config[:timeout]
    end

    test "build_host_config_with_limits includes memory and cpu limits" do
      strategy = BaseStrategy.new
      config = strategy.build_host_config_with_limits

      assert_equal 1024 * 1024 * 1024, config["Memory"]
      assert_equal 1024 * 1024 * 1024, config["MemorySwap"]
      assert_equal 100_000, config["CpuPeriod"]
      assert_equal 50_000, config["CpuQuota"]
      assert_equal 100, config["PidsLimit"]
    end

    test "read_file_from_container returns file content" do
      strategy = BaseStrategy.new

      @runtime_mock.expects(:exec).with("container-ref", [ "cat", "/path/to/test.txt" ])
        .returns([ [ "Hello, World!" ], [], 0 ])

      content = strategy.send(:read_file_from_container, "container-ref", "/path/to/test.txt")

      assert_equal "Hello, World!", content
    end

    test "read_file_from_container returns nil for missing file" do
      strategy = BaseStrategy.new

      @runtime_mock.expects(:exec).with("container-ref", [ "cat", "/missing/file" ])
        .returns([ [], [ "No such file" ], 1 ])

      content = strategy.send(:read_file_from_container, "container-ref", "/missing/file")

      assert_nil content
    end

    test "read_file_from_container handles errors" do
      strategy = BaseStrategy.new

      @runtime_mock.expects(:exec).raises(StandardError.new("connection error"))

      content = strategy.send(:read_file_from_container, "container-ref", "/any/file")

      assert_nil content
    end

    test "pull_image delegates to runtime and returns image" do
      strategy = TestStrategy.new

      @runtime_mock.expects(:pull_image).with("test-image:latest")

      result = strategy.pull_image

      assert_equal "test-image:latest", result[:image]
    end

    test "pull_image raises error when image is blank" do
      strategy = BaseStrategy.new
      strategy.define_singleton_method(:resolve_image) { nil }

      assert_raises(ArgumentError) do
        strategy.pull_image
      end
    end

    test "cleanup works with container_id" do
      strategy = TestStrategy.new

      @runtime_mock.expects(:resolve_container).with("abc123").returns("abc123")
      @runtime_mock.expects(:stop_container).with("abc123", 5)
      @runtime_mock.expects(:remove_container).with("abc123")

      result = strategy.cleanup(container_id: "abc123")
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup returns skipped when container_id is nil" do
      strategy = TestStrategy.new

      result = strategy.cleanup(container_id: nil)
      assert_equal :skipped, result[:status]
    end

    test "container_limits returns defaults when Settings not defined" do
      strategy = BaseStrategy.new

      limits = strategy.container_limits

      assert_equal 1024 * 1024 * 1024, limits[:memory_bytes]
      assert_equal 50_000, limits[:cpu_quota]
      assert_equal 100, limits[:pids_limit]
    end
  end
end
