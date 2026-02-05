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
  end
end
