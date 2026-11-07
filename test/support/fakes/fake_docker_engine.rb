# frozen_string_literal: true

module ContainerRuntime
  # The Docker Engine API, as far as ContainerRuntime::DockerRuntime calls it
  # for a session's container (inspect, exec, the archive API), served by
  # WebMock from a FakeMachine: the boundary is the daemon's HTTP API, so
  # DockerRuntime runs unchanged, through docker-api. The runtime contract
  # test drives DockerRuntime through this and RunnerRuntime through
  # FakeHostRunner, against the same machine.
  #
  #   engine = ContainerRuntime::FakeDockerEngine.new(machine).install!   # in setup
  #   engine.uninstall!                                                   # in teardown
  class FakeDockerEngine
    include WebMock::API

    URL = "http://docker.test:2375"
    BASE = %r{\Ahttp://docker\.test:2375}

    def initialize(machine)
      @machine = machine
      @exits = {}
    end

    def install!
      @previous_url = Docker.url
      Docker.url = URL
      stub_request(:get, %r{#{BASE}/version}).to_return(json(200, "Version" => "27.1.0", "ApiVersion" => "1.46"))
      stub_request(:get, %r{#{BASE}/containers/[^/]+/json}).to_return { |request| inspect_container(request) }
      stub_request(:post, %r{#{BASE}/containers/[^/]+/exec}).to_return { |request| create_exec(request) }
      stub_request(:post, %r{#{BASE}/exec/[^/]+/start}).to_return { |request| start_exec(request) }
      stub_request(:get, %r{#{BASE}/exec/[^/]+/json}).to_return { |request| inspect_exec(request) }
      stub_request(:put, %r{#{BASE}/containers/[^/]+/archive}).to_return { |request| put_archive(request) }
      stub_request(:get, %r{#{BASE}/containers/[^/]+/archive}).to_return { |request| get_archive(request) }
      self
    end

    def uninstall!
      Docker.url = @previous_url
    end

    private

    attr_reader :machine

    def container_for(request)
      ref = request.uri.path.split("/")[2]
      container = machine.container
      container if container && [ container.name, container.id ].include?(ref)
    end

    def inspect_container(request)
      container = container_for(request)
      return json(404, "message" => "No such container") if container.nil?

      json(200, "Id" => container.id, "Name" => "/#{container.name}",
                "State" => { "Running" => container.running, "Status" => container.running ? "running" : "exited",
                             "ExitCode" => container.exit_code.to_i, "OOMKilled" => container.oom_killed },
                "Config" => { "Labels" => { "aixle.session_id" => container.session_id.to_s } },
                "HostConfig" => {})
    end

    def create_exec(request)
      container = container_for(request)
      return json(404, "message" => "No such container") if container.nil?
      return json(409, "message" => "container #{container.id} is not running") unless container.running

      id = SecureRandom.hex(16)
      @exits[id] = JSON.parse(request.body).fetch("Cmd")
      json(201, "Id" => id)
    end

    def start_exec(request)
      id = request.uri.path.split("/")[2]
      stdout, stderr, code = machine.exec(@exits.fetch(id))
      @exits[id] = code
      { status: 200, body: frame(1, stdout) + frame(2, stderr), headers: { "Content-Type" => "application/vnd.docker.raw-stream" } }
    end

    def inspect_exec(request)
      json(200, "ExitCode" => @exits.fetch(request.uri.path.split("/")[2]), "Running" => false)
    end

    def put_archive(request)
      container = container_for(request)
      return json(404, "message" => "No such container") if container.nil?
      return json(500, "message" => "write /: no space left on device") if machine.fail_writes

      { status: 200, body: "" }
    end

    def get_archive(request)
      container = container_for(request)
      return json(404, "message" => "No such container") if container.nil?

      path = Rack::Utils.parse_query(request.uri.query)["path"]
      content = container.files[path]
      return json(404, "message" => "Could not find the file #{path}") if content.nil?

      { status: 200, body: tar(path, content), headers: { "Content-Type" => "application/x-tar" } }
    end

    # The multiplexed stream of an exec without a TTY: an 8-byte header (the
    # stream, three zero bytes, the size) before each frame.
    def frame(stream, text)
      return "".b if text.to_s.empty?

      [ stream, 0, 0, 0, text.bytesize ].pack("CCCCN") + text.b
    end

    def tar(path, content)
      io = StringIO.new("".b)
      Gem::Package::TarWriter.new(io) { |writer| writer.add_file_simple(File.basename(path), 0o644, content.bytesize) { |f| f.write(content) } }
      io.string
    end

    def json(status, body)
      { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end
  end
end
