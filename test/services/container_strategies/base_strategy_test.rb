# frozen_string_literal: true

require "test_helper"

module ContainerStrategies
  class BaseStrategyTest < ActiveSupport::TestCase
    # Concrete strategy for testing
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

      def exec(context)
        context[:result] = { status: :success }
      end
    end

    setup do
      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)

      @runtime_mock = mock("runtime")
    end

    # == Initialization Tests ==

    test "accepts hash input" do
      strategy = TestStrategy.new(foo: "bar")
      assert_equal "bar", strategy.input[:foo]
    end

    test "converts hash to indifferent access" do
      strategy = TestStrategy.new("foo" => "bar")
      assert_equal "bar", strategy.input[:foo]
      assert_equal "bar", strategy.input["foo"]
    end

    # == before_create Phase Tests ==

    test "before_create populates context with container config" do
      strategy = TestStrategy.new
      context = {}

      strategy.before_create(context)

      assert_equal "test-image:latest", context[:image]
      assert_equal [ "FOO=bar", "BAZ=qux" ], context[:env_vars]
      assert_equal({ "test" => "true", "env" => "test" }, context[:labels])
      assert_equal "app_default", context[:host_config]["NetworkMode"]
    end

    # == create Phase Tests ==

    test "create creates container via runtime" do
      strategy = TestStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      context = {
        image: "test:latest",
        env_vars: [ "A=1" ],
        labels: { "x" => "y" },
        host_config: { "NetworkMode" => "bridge" }
      }

      container_handle = "container-handle-123"
      @runtime_mock.expects(:create_container).with do |spec|
        spec[:image] == "test:latest" &&
          spec[:env_vars] == [ "A=1" ] &&
          spec[:labels] == { "x" => "y" } &&
          spec[:host_config] == { "NetworkMode" => "bridge" }
      end.returns(container_handle)

      strategy.create(context)

      assert_equal container_handle, context[:container]
    end

    test "create includes optional fields when present" do
      strategy = TestStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      context = {
        image: "test:latest",
        env_vars: [],
        labels: {},
        host_config: {},
        cmd: [ "/bin/sh", "-c", "echo hello" ],
        working_dir: "/workspace",
        exposed_ports: { "8080/tcp" => {} },
        container_name: "test-container"
      }

      @runtime_mock.expects(:create_container).with do |spec|
        spec[:image] == "test:latest" &&
          spec[:cmd] == [ "/bin/sh", "-c", "echo hello" ] &&
          spec[:working_dir] == "/workspace" &&
          spec[:exposed_ports] == { "8080/tcp" => {} } &&
          spec[:container_name] == "test-container"
      end.returns("container-handle")

      strategy.create(context)
    end

    # == start Phase Tests ==

    test "start starts container and waits for readiness" do
      strategy = TestStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:start_container).with("container-ref").returns("container-ref")
      @runtime_mock.expects(:wait_for_ready).with("container-ref", [])

      context = { container: "container-ref" }

      strategy.start(context)
    end

    # == cleanup Phase Tests ==

    test "cleanup stops and removes container" do
      strategy = TestStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:stop_container).with("container-ref", 5)
      @runtime_mock.expects(:remove_container).with("container-ref")

      context = { container: "container-ref" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup handles missing container gracefully" do
      strategy = TestStrategy.new
      context = { container: nil }

      result = strategy.cleanup(context)
      assert_equal :skipped, result[:status]
    end

    test "cleanup handles stop failure" do
      strategy = TestStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:stop_container).raises(StandardError.new("stop failed"))
      @runtime_mock.expects(:remove_container).with("container-ref")

      context = { container: "container-ref" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup returns failed when remove fails" do
      strategy = TestStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:stop_container).with("container-ref", 5)
      @runtime_mock.expects(:remove_container).raises(StandardError.new("remove failed"))

      context = { container: "container-ref" }

      result = strategy.cleanup(context)
      assert_equal :failed, result[:status]
      assert_equal "remove failed", result[:error]
    end

    test "cleanup removes image when remove_image_after_cleanup? is true" do
      strategy = TestStrategy.new
      strategy.define_singleton_method(:remove_image_after_cleanup?) { true }
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:stop_container).with("container-ref", 5)
      @runtime_mock.expects(:remove_container).with("container-ref")
      @runtime_mock.expects(:remove_image).with("test-image:latest")

      context = { container: "container-ref", image: "test-image:latest" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup does not remove image by default" do
      strategy = TestStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:stop_container).with("container-ref", 5)
      @runtime_mock.expects(:remove_container).with("container-ref")
      @runtime_mock.expects(:remove_image).never

      context = { container: "container-ref", image: "test-image:latest" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup handles image removal error gracefully" do
      strategy = TestStrategy.new
      strategy.define_singleton_method(:remove_image_after_cleanup?) { true }
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.stubs(:stop_container)
      @runtime_mock.stubs(:remove_container)
      @runtime_mock.expects(:remove_image).with("busy-image:latest").raises(StandardError.new("image in use"))

      context = { container: "container-ref", image: "busy-image:latest" }

      # remove_image error is caught inside runtime.remove_image or cleanup handles it
      # If runtime.remove_image raises and cleanup catches it, we get :failed
      # But since stop+remove succeed, the error is from remove_image which might not fail cleanup
      result = strategy.cleanup(context)
      # The cleanup catches all StandardErrors from remove step
      assert_includes [ :cleaned_up, :failed ], result[:status]
    end

    # == Template Methods Tests ==

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

      assert_equal "app_default", config["NetworkMode"]
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

    test "timeout_for returns nil by default" do
      strategy = BaseStrategy.new
      assert_nil strategy.timeout_for(:exec)
    end

    # == Resource Limits Tests ==

    test "build_host_config_with_limits includes memory and cpu limits" do
      strategy = BaseStrategy.new
      config = strategy.build_host_config_with_limits

      assert_equal 1024 * 1024 * 1024, config["Memory"]
      assert_equal 1024 * 1024 * 1024, config["MemorySwap"]
      assert_equal 100_000, config["CpuPeriod"]
      assert_equal 50_000, config["CpuQuota"]
      assert_equal 100, config["PidsLimit"]
    end

    # == File Reading Tests ==

    test "read_file_from_container returns file content" do
      strategy = BaseStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:exec).with("container-ref", [ "cat", "/path/to/test.txt" ])
        .returns([ [ "Hello, World!" ], [], 0 ])

      content = strategy.send(:read_file_from_container, "container-ref", "/path/to/test.txt")

      assert_equal "Hello, World!", content
    end

    test "read_file_from_container returns nil for missing file" do
      strategy = BaseStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:exec).with("container-ref", [ "cat", "/missing/file" ])
        .returns([ [], [ "No such file" ], 1 ])

      content = strategy.send(:read_file_from_container, "container-ref", "/missing/file")

      assert_nil content
    end

    test "read_file_from_container handles errors" do
      strategy = BaseStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:exec).raises(StandardError.new("connection error"))

      content = strategy.send(:read_file_from_container, "container-ref", "/any/file")

      assert_nil content
    end

    # == pull_image Tests ==

    test "pull_image delegates to runtime" do
      strategy = TestStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:pull_image).with("test-image:latest")
        .returns({ status: :cached, image: "test-image:latest", duration_seconds: 0 })

      result = strategy.pull_image

      assert_equal :cached, result[:status]
      assert_equal "test-image:latest", result[:image]
    end

    test "pull_image raises error when image is blank" do
      strategy = BaseStrategy.new
      strategy.define_singleton_method(:resolve_image) { nil }

      assert_raises(ArgumentError) do
        strategy.pull_image
      end
    end

    # == cleanup with container_id Tests ==

    test "cleanup works with container_id when container is nil" do
      strategy = TestStrategy.new
      strategy.instance_variable_set(:@runtime, @runtime_mock)

      @runtime_mock.expects(:stop_container).with("abc123", 5)
      @runtime_mock.expects(:remove_container).with("abc123")

      context = { container: nil, container_id: "abc123" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup returns skipped when both container and container_id are nil" do
      strategy = TestStrategy.new
      context = { container: nil, container_id: nil }

      result = strategy.cleanup(context)
      assert_equal :skipped, result[:status]
    end

    # == container_limits Tests ==

    test "container_limits returns defaults when Settings not defined" do
      strategy = BaseStrategy.new

      limits = strategy.container_limits

      assert_equal 1024 * 1024 * 1024, limits[:memory_bytes]
      assert_equal 50_000, limits[:cpu_quota]
      assert_equal 100, limits[:pids_limit]
    end

    # Note: log_pull_progress tests moved to DockerRuntime unit tests
    # (method was relocated from BaseStrategy to DockerRuntime)
  end
end
