# frozen_string_literal: true

require "test_helper"

module ContainerRuntime
  class DockerRuntimeTest < ActiveSupport::TestCase
    setup do
      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:debug)
      @runtime = DockerRuntime.new
    end

    test "pull_image raises when image blank" do
      assert_raises(ArgumentError) { @runtime.pull_image("") }
      assert_raises(ArgumentError) { @runtime.pull_image(nil) }
    end

    test "pull_image returns cached when image exists" do
      Docker::Image.stubs(:get).with("alpine:latest").returns(mock("image"))

      result = @runtime.pull_image("alpine:latest")

      assert_equal :cached, result[:status]
      assert_equal "alpine:latest", result[:image]
      assert_equal 0, result[:duration_seconds]
    end

    test "pull_image pulls and returns pulled when image not cached" do
      Docker::Image.stubs(:get).with("alpine:latest").raises(Docker::Error::NotFoundError)
      Docker::Image.stubs(:create).with("fromImage" => "alpine", "tag" => "latest").yields("{}")

      result = @runtime.pull_image("alpine:latest")

      assert_equal :pulled, result[:status]
      assert_equal "alpine:latest", result[:image]
      assert result[:duration_seconds].is_a?(Integer)
    end

    test "create_container builds config from spec" do
      container_mock = mock("container")
      Docker::Container.expects(:create).with do |config|
        config["Image"] == "alpine:latest" &&
          config["Env"] == [ "FOO=bar" ] &&
          config["Labels"] == { "app" => "test" } &&
          config["HostConfig"] == { "NetworkMode" => "bridge" }
      end.returns(container_mock)

      spec = {
        image: "alpine:latest",
        env_vars: [ "FOO=bar" ],
        labels: { "app" => "test" },
        host_config: { "NetworkMode" => "bridge" }
      }

      result = @runtime.create_container(spec)

      assert_equal container_mock, result
    end

    test "create_container includes optional fields" do
      container_mock = mock("container")
      Docker::Container.expects(:create).with do |config|
        config["Cmd"] == [ "/bin/sh", "-c", "echo hi" ] &&
          config["WorkingDir"] == "/workspace" &&
          config["ExposedPorts"] == { "8080/tcp" => {} } &&
          config["name"] == "my-container"
      end.returns(container_mock)

      spec = {
        image: "alpine:latest",
        env_vars: [],
        labels: {},
        host_config: {},
        cmd: [ "/bin/sh", "-c", "echo hi" ],
        working_dir: "/workspace",
        exposed_ports: { "8080/tcp" => {} },
        container_name: "my-container"
      }

      @runtime.create_container(spec)
    end

    test "resolve_container returns container when given Docker::Container" do
      container = mock("Docker::Container")
      container.stubs(:is_a?).with(Docker::Container).returns(true)

      result = @runtime.resolve_container(container)

      assert_equal container, result
    end

    test "resolve_container fetches by id when given string" do
      container_mock = mock("container")
      Docker::Container.stubs(:get).with("abc123").returns(container_mock)

      result = @runtime.resolve_container("abc123")

      assert_equal container_mock, result
    end

    test "resolve_container returns nil when container not found" do
      Docker::Container.stubs(:get).with("nonexistent").raises(Docker::Error::NotFoundError)

      result = @runtime.resolve_container("nonexistent")

      assert_nil result
    end

    test "container_identifier returns nil for blank" do
      assert_nil @runtime.container_identifier(nil)
      assert_nil @runtime.container_identifier("")
    end

    test "container_identifier returns string when given string" do
      assert_equal "abc123", @runtime.container_identifier("abc123")
    end

    test "container_identifier returns truncated id when container has id" do
      container = mock("container")
      container.stubs(:id).returns("abcdef1234567890")

      # id[0..11] = first 12 chars
      assert_equal "abcdef123456", @runtime.container_identifier(container)
    end

    test "copy_to executes base64 write via container exec" do
      container_mock = mock("container")
      encoded = Base64.strict_encode64("hello")
      container_mock.expects(:exec).with(
        [ "/bin/sh", "-c", "mkdir -p /tmp && echo '#{encoded}' | base64 -d > /tmp/file.txt" ]
      ).returns([ [], [], 0 ])
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      assert @runtime.copy_to("cid", "/tmp/file.txt", "hello")
    end

    test "copy_from delegates to container read_file" do
      container_mock = mock("container")
      container_mock.expects(:read_file).with("/path/to/file").returns("file content")
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      result = @runtime.copy_from("cid", "/path/to/file")

      assert_equal "file content", result
    end

    test "stop_container delegates to container" do
      container_mock = mock("container")
      container_mock.expects(:stop).with({})
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      @runtime.stop_container("cid")
    end

    test "remove_container delegates to container" do
      container_mock = mock("container")
      container_mock.expects(:remove).with({})
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      @runtime.remove_container("cid")
    end

    test "remove_image is no-op when image blank" do
      Docker::Image.expects(:get).never

      @runtime.remove_image("")
      @runtime.remove_image(nil)
    end
  end
end
