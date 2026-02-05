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

    test "create creates Docker container with config" do
      strategy = TestStrategy.new
      context = {
        image: "test:latest",
        env_vars: [ "A=1" ],
        labels: { "x" => "y" },
        host_config: { "NetworkMode" => "bridge" }
      }

      container_mock = mock("container")
      Docker::Container.expects(:create).with { |config|
        config["Image"] == "test:latest" &&
        config["Env"] == [ "A=1" ] &&
        config["Labels"] == { "x" => "y" } &&
        config["HostConfig"] == { "NetworkMode" => "bridge" }
      }.returns(container_mock)

      strategy.create(context)

      assert_equal container_mock, context[:container]
    end

    test "create includes optional fields when present" do
      strategy = TestStrategy.new
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

      Docker::Container.expects(:create).with { |config|
        config["Image"] == "test:latest" &&
        config["Env"] == [] &&
        config["Labels"] == {} &&
        config["HostConfig"] == {} &&
        config["Cmd"] == [ "/bin/sh", "-c", "echo hello" ] &&
        config["WorkingDir"] == "/workspace" &&
        config["ExposedPorts"] == { "8080/tcp" => {} } &&
        config["name"] == "test-container"
      }.returns(mock("container"))

      strategy.create(context)
    end

    # == start Phase Tests ==

    test "start starts container and waits for health" do
      strategy = TestStrategy.new
      container_mock = mock("container")

      # Setup container mock
      container_mock.expects(:start).once
      container_mock.expects(:refresh!).at_least_once
      container_mock.stubs(:json).returns({
        "State" => { "Running" => true, "Status" => "running" }
      })

      context = { container: container_mock }

      strategy.start(context)
    end

    test "start raises error when container exits" do
      strategy = TestStrategy.new
      container_mock = mock("container")

      container_mock.expects(:start).once
      container_mock.expects(:refresh!).at_least_once
      container_mock.stubs(:json).returns({
        "State" => { "Running" => false, "Status" => "exited", "ExitCode" => 1 }
      })

      context = { container: container_mock }

      error = assert_raises(RuntimeError) do
        strategy.start(context)
      end

      assert_match(/exited with code 1/, error.message)
    end

    # == cleanup Phase Tests ==

    test "cleanup stops and removes container" do
      strategy = TestStrategy.new
      container_mock = mock("container")

      container_mock.stubs(:id).returns("abc123456789")
      container_mock.expects(:stop).with("t" => 5).once
      container_mock.expects(:remove).once

      context = { container: container_mock }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup handles missing container gracefully" do
      strategy = TestStrategy.new
      context = { container: nil }

      # Should not raise
      strategy.cleanup(context)
      assert true, "Cleanup completed without error"
    end

    test "cleanup handles NotFoundError on stop" do
      strategy = TestStrategy.new
      container_mock = mock("container")

      container_mock.stubs(:id).returns("abc123456789")
      container_mock.expects(:stop).raises(Docker::Error::NotFoundError, "not found")

      context = { container: container_mock }

      result = strategy.cleanup(context)
      assert_equal :not_found, result[:status]
    end

    test "cleanup handles NotFoundError on remove" do
      strategy = TestStrategy.new
      container_mock = mock("container")

      container_mock.stubs(:id).returns("abc123456789")
      container_mock.expects(:stop).once
      container_mock.expects(:remove).raises(Docker::Error::NotFoundError, "not found")

      context = { container: container_mock }

      result = strategy.cleanup(context)
      assert_equal :not_found, result[:status]
    end

    test "cleanup removes image when remove_image_after_cleanup? is true" do
      strategy = TestStrategy.new
      strategy.define_singleton_method(:remove_image_after_cleanup?) { true }

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.expects(:stop).once
      container_mock.expects(:remove).once

      image_mock = mock("image")
      image_mock.expects(:remove).with(force: true).once
      Docker::Image.expects(:get).with("test-image:latest").returns(image_mock)

      context = { container: container_mock, image: "test-image:latest" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup does not remove image by default" do
      strategy = TestStrategy.new

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.expects(:stop).once
      container_mock.expects(:remove).once

      # Docker::Image.get should NOT be called
      Docker::Image.expects(:get).never

      context = { container: container_mock, image: "test-image:latest" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup handles image in use by another container" do
      strategy = TestStrategy.new
      strategy.define_singleton_method(:remove_image_after_cleanup?) { true }

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.stubs(:stop)
      container_mock.stubs(:remove)

      image_mock = mock("image")
      image_mock.expects(:remove).raises(Docker::Error::ConflictError, "image in use")
      Docker::Image.expects(:get).with("busy-image:latest").returns(image_mock)

      context = { container: container_mock, image: "busy-image:latest" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
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
      container_mock = mock("container")

      # exec returns [stdout_array, stderr_array, exit_code]
      container_mock.expects(:exec).with([ "cat", "/path/to/test.txt" ]).returns(
        [ [ "Hello, World!" ], [], 0 ]
      )

      content = strategy.send(:read_file_from_container, container_mock, "/path/to/test.txt")

      assert_equal "Hello, World!", content
    end

    test "read_file_from_container returns nil for missing file" do
      strategy = BaseStrategy.new
      container_mock = mock("container")

      # Exit code 1 = file not found
      container_mock.expects(:exec).with([ "cat", "/missing/file" ]).returns(
        [ [], [ "cat: /missing/file: No such file or directory" ], 1 ]
      )

      content = strategy.send(:read_file_from_container, container_mock, "/missing/file")

      assert_nil content
    end

    test "read_file_from_container handles container not found" do
      strategy = BaseStrategy.new
      container_mock = mock("container")

      container_mock.expects(:exec).raises(Docker::Error::NotFoundError, "not found")

      content = strategy.send(:read_file_from_container, container_mock, "/any/file")

      assert_nil content
    end

    # == pull_image Tests ==

    test "pull_image returns cached when image exists" do
      strategy = TestStrategy.new
      Docker::Image.expects(:get).with("test-image:latest").returns(mock("image"))

      result = strategy.pull_image

      assert_equal :cached, result[:status]
      assert_equal "test-image:latest", result[:image]
      assert_equal 0, result[:duration_seconds]
    end

    test "pull_image pulls image when not cached" do
      strategy = TestStrategy.new
      Docker::Image.expects(:get).with("test-image:latest").raises(Docker::Error::NotFoundError, "not found")
      Docker::Image.expects(:create).with(
        "fromImage" => "test-image",
        "tag" => "latest"
      ).yields('{"status": "Pulling"}').returns(mock("image"))

      result = strategy.pull_image

      assert_equal :pulled, result[:status]
      assert_equal "test-image:latest", result[:image]
    end

    test "pull_image raises error when image is blank" do
      strategy = BaseStrategy.new
      strategy.define_singleton_method(:resolve_image) { nil }

      assert_raises(ArgumentError) do
        strategy.pull_image
      end
    end

    test "pull_image parses image without tag" do
      strategy = BaseStrategy.new
      strategy.define_singleton_method(:resolve_image) { "my-image" }
      Docker::Image.expects(:get).with("my-image").raises(Docker::Error::NotFoundError, "not found")
      Docker::Image.expects(:create).with(
        "fromImage" => "my-image",
        "tag" => "latest"
      ).returns(mock("image"))

      result = strategy.pull_image
      assert_equal :pulled, result[:status]
    end

    # == cleanup with container_id Tests ==

    test "cleanup gets container by id when container object is nil" do
      strategy = TestStrategy.new
      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.expects(:stop).with("t" => 5).once
      container_mock.expects(:remove).once

      Docker::Container.expects(:get).with("abc123").returns(container_mock)

      context = { container: nil, container_id: "abc123" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup returns not_found when container_id lookup fails" do
      strategy = TestStrategy.new
      Docker::Container.expects(:get).with("missing").raises(Docker::Error::NotFoundError, "not found")

      context = { container: nil, container_id: "missing" }

      result = strategy.cleanup(context)
      assert_equal :not_found, result[:status]
    end

    test "cleanup returns skipped when both container and container_id are nil" do
      strategy = TestStrategy.new
      context = { container: nil, container_id: nil }

      result = strategy.cleanup(context)
      assert_equal :skipped, result[:status]
    end

    # == cleanup error handling Tests ==

    test "cleanup force removes on stop error" do
      strategy = TestStrategy.new
      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.expects(:stop).raises(StandardError, "timeout")
      container_mock.expects(:remove).with(force: true).once

      context = { container: container_mock }

      result = strategy.cleanup(context)
      assert_equal :force_removed, result[:status]
    end

    test "cleanup force removes on remove error" do
      strategy = TestStrategy.new
      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.expects(:stop).once
      container_mock.expects(:remove).raises(StandardError, "error")
      container_mock.expects(:remove).with(force: true).once

      context = { container: container_mock }

      result = strategy.cleanup(context)
      assert_equal :force_removed, result[:status]
    end

    test "cleanup handles force remove failure" do
      strategy = TestStrategy.new
      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.expects(:stop).raises(StandardError, "error")
      container_mock.expects(:remove).with(force: true).raises(StandardError, "force failed")

      context = { container: container_mock }

      result = strategy.cleanup(context)
      assert_equal :failed, result[:status]
      assert_equal "force failed", result[:error]
    end

    # == wait_for_services Tests ==

    class TestStrategyWithPorts < BaseStrategy
      def resolve_image
        "test-image:latest"
      end

      def services_ports
        [ 8080, 3000 ]
      end
    end

    test "wait_for_services returns immediately when no ports" do
      strategy = TestStrategy.new
      container_mock = mock("container")

      result = strategy.wait_for_services(container_mock)
      assert_nil result # returns nil from empty block
    end

    test "wait_for_services checks ports" do
      strategy = TestStrategyWithPorts.new
      container_mock = mock("container")

      # Simulate ports being open
      container_mock.stubs(:exec).returns([ [ "open" ], [], 0 ])

      result = strategy.wait_for_services(container_mock, timeout: 2)
      assert_equal true, result
    end

    test "wait_for_services times out when ports not ready" do
      strategy = TestStrategyWithPorts.new
      container_mock = mock("container")
      Rails.logger.stubs(:debug)

      # Simulate ports not open
      container_mock.stubs(:exec).returns([ [], [], 1 ])

      result = strategy.wait_for_services(container_mock, timeout: 1)
      assert_equal false, result
    end

    # == port_open? Tests ==

    test "port_open? returns true when port is open" do
      strategy = BaseStrategy.new
      container_mock = mock("container")

      # Port 8080 = 0x1F90
      container_mock.expects(:exec).returns([ [ "open" ], [], 0 ])

      assert strategy.port_open?(container_mock, 8080)
    end

    test "port_open? returns false on exec error" do
      strategy = BaseStrategy.new
      container_mock = mock("container")
      Rails.logger.stubs(:debug)

      container_mock.expects(:exec).raises(StandardError, "error")

      refute strategy.port_open?(container_mock, 8080)
    end

    # == wait_for_container_health timeout Tests ==

    test "wait_for_container_health raises on timeout" do
      strategy = BaseStrategy.new
      container_mock = mock("container")

      container_mock.stubs(:refresh!)
      container_mock.stubs(:json).returns({
        "State" => { "Running" => false, "Status" => "created" }
      })

      error = assert_raises(RuntimeError) do
        strategy.wait_for_container_health(container_mock, timeout: 0.1)
      end

      assert_match(/failed to start within/, error.message)
    end

    test "wait_for_container_health raises on dead state" do
      strategy = BaseStrategy.new
      container_mock = mock("container")

      container_mock.stubs(:refresh!)
      container_mock.stubs(:json).returns({
        "State" => { "Running" => false, "Status" => "dead", "ExitCode" => 137 }
      })

      error = assert_raises(RuntimeError) do
        strategy.wait_for_container_health(container_mock, timeout: 1)
      end

      assert_match(/exited with code 137/, error.message)
    end

    # == cleanup_image error handling Tests ==

    test "cleanup_image handles image not found" do
      strategy = TestStrategy.new
      strategy.define_singleton_method(:remove_image_after_cleanup?) { true }

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.stubs(:stop)
      container_mock.stubs(:remove)

      Docker::Image.expects(:get).with("missing:latest").raises(Docker::Error::NotFoundError, "not found")

      context = { container: container_mock, image: "missing:latest" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    test "cleanup_image handles generic error" do
      strategy = TestStrategy.new
      strategy.define_singleton_method(:remove_image_after_cleanup?) { true }

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.stubs(:stop)
      container_mock.stubs(:remove)

      image_mock = mock("image")
      image_mock.expects(:remove).raises(StandardError, "unknown error")
      Docker::Image.expects(:get).with("error:latest").returns(image_mock)

      context = { container: container_mock, image: "error:latest" }

      result = strategy.cleanup(context)
      assert_equal :cleaned_up, result[:status]
    end

    # == container_limits Tests ==

    test "container_limits returns defaults when Settings not defined" do
      strategy = BaseStrategy.new

      limits = strategy.container_limits

      assert_equal 1024 * 1024 * 1024, limits[:memory_bytes]
      assert_equal 50_000, limits[:cpu_quota]
      assert_equal 100, limits[:pids_limit]
    end

    # == read_file_from_container error handling ==

    test "read_file_from_container handles generic error" do
      strategy = BaseStrategy.new
      container_mock = mock("container")

      container_mock.expects(:exec).raises(StandardError, "connection error")

      content = strategy.send(:read_file_from_container, container_mock, "/test/file")

      assert_nil content
    end

    # == log_pull_progress Tests ==

    test "log_pull_progress handles non-string chunk" do
      strategy = BaseStrategy.new
      Rails.logger.stubs(:debug)

      # Should not raise
      strategy.send(:log_pull_progress, nil)
      strategy.send(:log_pull_progress, 123)
      assert true
    end

    test "log_pull_progress handles invalid JSON" do
      strategy = BaseStrategy.new
      Rails.logger.stubs(:debug)

      # Should not raise
      strategy.send(:log_pull_progress, "not json")
      assert true
    end

    test "log_pull_progress logs status with progress" do
      strategy = BaseStrategy.new
      Rails.logger.expects(:debug).once

      strategy.send(:log_pull_progress, '{"status": "Downloading", "progress": "50%"}')
    end
  end
end
