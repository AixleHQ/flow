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
      assert_kind_of Integer, result[:duration_seconds]
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

    test "write_file writes file via tar archive API" do
      container_mock = mock("container")
      container_mock.expects(:archive_in_stream).with("/", overwrite: true).multiple_yields
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      assert @runtime.write_file("cid", "/tmp/file.txt", "hello", uid: 1001, gid: 1001)
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

    test "start_container resolves, starts and returns the container" do
      container_mock = mock("container")
      container_mock.expects(:start)
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      result = @runtime.start_container("cid")

      assert_equal container_mock, result
    end

    test "exec resolves the container and returns its exec result" do
      container_mock = mock("container")
      container_mock.expects(:exec).with([ "echo", "hi" ], {}).returns([ [ "hi\n" ], [], 0 ])
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      result = @runtime.exec("cid", [ "echo", "hi" ])

      assert_equal [ [ "hi\n" ], [], 0 ], result
    end

    test "exec translates the runtime-agnostic timeout option into docker-api's wait" do
      container_mock = mock("container")
      container_mock.expects(:exec)
        .with([ "sleep", "120" ], { wait: 300 })
        .returns([ [], [], 0 ])
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      @runtime.exec("cid", [ "sleep", "120" ], timeout: 300)
    end

    test "exec leaves the caller's options hash untouched" do
      container_mock = mock("container")
      container_mock.stubs(:exec).returns([ [], [], 0 ])
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      opts = { timeout: 300 }
      @runtime.exec("cid", [ "echo", "hi" ], opts)

      assert_equal({ timeout: 300 }, opts)
    end

    test "read_file extracts the file body matching basename from the tar archive" do
      tar_bytes = build_test_tar("tmp/hello.txt", "file body")
      container_mock = mock("container")
      container_mock.stubs(:archive_out).with("/tmp/hello.txt").yields(tar_bytes)
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      assert_equal "file body", @runtime.read_file("cid", "/tmp/hello.txt")
    end

    # archive_out tars the requested path, so its single file entry IS the answer even
    # when the header name doesn't match: past 100 bytes tar truncates that name (see
    # BaseRuntime#extract_from_tar), and trusting it dropped long-named session outputs.
    test "read_file returns the archive's file entry even when the header name differs" do
      tar_bytes = build_test_tar("tmp/truncated-by-tar", "file body")
      container_mock = mock("container")
      container_mock.stubs(:archive_out).with("/tmp/hello.txt").yields(tar_bytes)
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      assert_equal "file body", @runtime.read_file("cid", "/tmp/hello.txt")
    end

    test "read_file returns nil when the tar carries no file entry" do
      container_mock = mock("container")
      container_mock.stubs(:archive_out).with("/tmp/hello.txt").yields(build_empty_tar)
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      assert_nil @runtime.read_file("cid", "/tmp/hello.txt")
    end

    test "wait_container waits with the default timeout and returns the wait result" do
      container_mock = mock("container")
      container_mock.expects(:wait).with(1800).returns({ "StatusCode" => 0 })
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      assert_equal({ "StatusCode" => 0 }, @runtime.wait_container("cid"))
    end

    test "wait_container passes an explicit timeout through to the container" do
      container_mock = mock("container")
      container_mock.expects(:wait).with(5).returns({ "StatusCode" => 137 })
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      assert_equal({ "StatusCode" => 137 }, @runtime.wait_container("cid", 5))
    end

    test "container_logs demultiplexes stdout and stderr frames" do
      container_mock = mock("container")
      container_mock.stubs(:logs).with(stdout: true, stderr: false).returns(docker_log_frame("out\n"))
      container_mock.stubs(:logs).with(stdout: false, stderr: true).returns(docker_log_frame("err\n"))
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      result = @runtime.container_logs("cid")

      assert_equal "out\n", result[:stdout]
      assert_equal "err\n", result[:stderr]
    end

    test "container_logs concatenates multiple demuxed frames on the same stream" do
      framed = docker_log_frame("line1\n") + docker_log_frame("line2\n")
      container_mock = mock("container")
      container_mock.stubs(:logs).with(stdout: true, stderr: false).returns(framed)
      container_mock.stubs(:logs).with(stdout: false, stderr: true).returns("")
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      result = @runtime.container_logs("cid")

      assert_equal "line1\nline2\n", result[:stdout]
      assert_equal "", result[:stderr]
    end

    test "remove_image gets and force-removes the image when present" do
      docker_image = mock("image")
      docker_image.expects(:remove).with(force: true)
      Docker::Image.stubs(:get).with("alpine:latest").returns(docker_image)

      @runtime.remove_image("alpine:latest")
    end

    test "image_digest returns the first repo digest" do
      image_mock = mock("image")
      image_mock.stubs(:info).returns({ "RepoDigests" => [ "alpine@sha256:abc", "alpine@sha256:def" ] })
      Docker::Image.stubs(:get).with("alpine:latest").returns(image_mock)

      assert_equal "alpine@sha256:abc", @runtime.image_digest("alpine:latest")
    end

    test "image_digest returns nil when image blank" do
      Docker::Image.expects(:get).never

      assert_nil @runtime.image_digest("")
      assert_nil @runtime.image_digest(nil)
    end

    test "wait_for_ready returns true when container is running with no ports and no traffic route" do
      container_mock = mock("container")
      container_mock.stubs(:refresh!)
      container_mock.stubs(:json).returns("State" => { "Running" => true }, "Name" => "/worker-1")
      Docker::Container.stubs(:get).with("cid").returns(container_mock)

      assert @runtime.wait_for_ready("cid")
    end

    test "container_identifier falls back to to_s when id is not a usable string" do
      container_mock = mock("container")
      container_mock.stubs(:id).returns(nil)
      container_mock.stubs(:to_s).returns("Custom#123")

      assert_equal "Custom#123", @runtime.container_identifier(container_mock)
    end

    # == Garbage-collection primitives ==

    test "list_session_resources describes session containers, exited ones included" do
      Docker::Container.expects(:all)
        .with(all: true, filters: { label: [ "aixle.session_id" ] }.to_json)
        .returns([
          session_container("terminal-abc123", created: 1_764_000_000),
          session_container("aixle-tool-xyz", created: 1_764_000_500)
        ])

      resources = @runtime.list_session_resources

      assert_equal [ "Container", "Container" ], resources.map(&:kind)
      assert_equal [ "terminal-abc123", "aixle-tool-xyz" ], resources.map(&:name)
      # A tool container has no route token, so it has no provable owner and the
      # sweeper keeps it.
      assert_equal [ "abc123", nil ], resources.map(&:route_token)
      assert_equal Time.zone.at(1_764_000_000), resources.first.created_at
    end

    test "list_session_resources reports nothing when the daemon is unreachable" do
      Docker::Container.stubs(:all).raises(StandardError.new("connection refused"))

      assert_empty @runtime.list_session_resources
    end

    test "delete_session_resource removes the container and treats an already-gone one as success" do
      container_mock = mock("container")
      container_mock.expects(:remove).with(force: true)
      Docker::Container.expects(:get).with("terminal-abc123").returns(container_mock)
      Docker::Container.expects(:get).with("terminal-gone").raises(Docker::Error::NotFoundError)

      assert @runtime.delete_session_resource(session_resource("terminal-abc123"))
      assert @runtime.delete_session_resource(session_resource("terminal-gone"))
      assert_not @runtime.delete_session_resource(session_resource(""))
    end

    test "delete_session_resource reports false when removal fails" do
      Docker::Container.stubs(:get).with("terminal-stuck").raises(Docker::Error::ServerError)

      assert_not @runtime.delete_session_resource(session_resource("terminal-stuck"))
    end

    private

    def session_container(name, created:)
      container = mock("container")
      container.stubs(:info).returns("Names" => [ "/#{name}" ], "Id" => "abcdef0123456789", "Created" => created)
      container
    end

    def session_resource(name)
      ContainerRuntime::SessionResource.new(kind: "Container", name: name, route_token: "abc123")
    end

    def build_test_tar(filename, content)
      io = StringIO.new
      io.binmode
      Gem::Package::TarWriter.new(io) do |tar|
        tar.add_file_simple(filename, 0o644, content.bytesize) { |f| f.write(content) }
      end
      io.string
    end

    def build_empty_tar
      io = StringIO.new
      io.binmode
      Gem::Package::TarWriter.new(io) { |tar| tar.mkdir("tmp", 0o755) }
      io.string
    end

    # Frame a payload the way Docker's multiplexed log stream does:
    # 8-byte header [stream_type(1) | padding(3) | size(4 big-endian)] then payload.
    def docker_log_frame(payload, stream_type: 1)
      [ stream_type, 0, 0, 0 ].pack("C4") + [ payload.bytesize ].pack("N") + payload
    end
  end
end
