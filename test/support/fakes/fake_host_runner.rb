# frozen_string_literal: true

module ContainerRuntime
  # The host runner of one or more `manual` machines, in the test process: it
  # answers every op Runners::Operations.enqueue! puts on a machine's queue, the
  # moment it is enqueued, with the result runner/protocol/PROTOCOL.md §6
  # specifies for it, against an in-memory machine (FakeMachine). That is the
  # boundary ContainerRuntime::RunnerRuntime talks to: the queue and the op
  # results, not the gateway's HTTP, which RunnerGatewayOperationsTest and the
  # conformance fixtures cover, nor the Go runner's Docker calls, which its own
  # tests cover.
  #
  #   runner = ContainerRuntime::FakeHostRunner.new(environment)
  #   runner.machine.on_exec { |cmd| [ "out", "", 0 ] }
  #   ... RunnerRuntime calls ...
  #   runner.operations  # => [{ op:, session_id:, payload: }, ...]
  #   runner.stop
  #
  # `answer_with` replaces the answer of one op name, to simulate a runner that
  # expires an op, a reset that fails, or one that never answers (`:none`).
  class FakeHostRunner
    attr_reader :machine, :operations

    def initialize(*environments, machine: nil)
      @environment_ids = environments.map(&:id)
      @machine = machine || FakeMachine.new(key: environments.first.key)
      @operations = []
      @overrides = {}
      @subscriber = ActiveSupport::Notifications.subscribe("enqueued.runner_operations") do |*, payload|
        answer(payload[:operation]) if @environment_ids.include?(payload[:environment_id])
      end
    end

    def stop
      ActiveSupport::Notifications.unsubscribe(@subscriber)
    end

    # `result` is a Hash in the shape of a result body (PROTOCOL.md §5.5), or
    # `:none` for no answer at all.
    def answer_with(op, result = nil, &block)
      @overrides[op] = block || ->(*) { result }
    end

    def ops
      operations.pluck(:op)
    end

    private

    def answer(operation)
      payload = operation.payload
      session_id = operation.terminal_session_id
      @operations << { op: operation.op, session_id: session_id, payload: payload }
      result = @overrides[operation.op]&.call(payload, session_id) || run(operation.op, payload, session_id)
      return if result == :none

      Runners::Operations.record_result!(operation, status: result.fetch("status"), result: result.except("status"))
    end

    def run(op, payload, session_id)
      case op
      when "image.ensure" then ok("data" => { "pulled" => !machine.image?(payload), "duration_ms" => 0 }).tap { machine.pull(payload) }
      when "container.start" then container_start(payload, session_id)
      when "container.stop" then container_stop(session_id)
      when "env.reset" then ok("data" => { "removed_containers" => machine.reset, "removed_volumes" => [] })
      when "env.scrub" then ok("data" => { "removed_containers" => machine.reset, "outputs_emptied" => false })
      when "status" then status(session_id)
      else session_op(op, payload, session_id)
      end
    end

    def container_start(payload, session_id)
      container = machine.container
      return mismatch(container, session_id) if container&.session_id && container.session_id != session_id
      return error("container_exists", "the environment already has #{container.name}") if container

      container = machine.start(session_id, payload)
      ok("data" => { "container_id" => container.id, "name" => container.name })
    end

    def container_stop(session_id)
      container = machine.container
      return error("no_session_container", "the environment has no session container") if container.nil?
      return mismatch(container, session_id) if container.session_id != session_id

      ok("data" => { "removed" => machine.stop(session_id) })
    end

    def status(session_id)
      container = machine.container
      return ok("data" => { "state" => "missing" }) if container.nil?
      return mismatch(container, session_id) if container.session_id != session_id

      data = { "state" => container.running ? "running" : "terminated", "container_id" => container.id, "name" => container.name }
      data.merge!("exit_code" => container.exit_code, "oom_killed" => container.oom_killed) unless container.running
      ok("data" => data)
    end

    def session_op(op, payload, session_id)
      container = machine.container
      return error("no_session_container", "the environment has no session container") if container.nil?
      return mismatch(container, session_id) if container.session_id != session_id

      case op
      when "exec"
        return error("no_session_container", "the session container is not running") unless container.running

        stdout, stderr, code = machine.exec(payload.fetch("cmd"))
        ok("exit_code" => code, "stdout" => stdout, "stderr" => stderr,
           "data" => { "stdout_truncated" => false, "stderr_truncated" => false })
      when "write_file"
        return error("write_failed", "writing #{payload['path']} failed") unless machine.write(payload)

        ok
      when "read_file"
        content = container.files[payload.fetch("path")]
        return error("file_not_found", "#{payload['path']} does not exist") if content.nil?

        ok("data" => { "content" => Base64.strict_encode64(content), "size" => content.bytesize })
      when "logs"
        tail = container.files["/tmp/terminal_output.log"].to_s
        ok("data" => { "tail" => tail, "size" => tail.bytesize, "truncated" => false })
      else
        error("unsupported_op", "the fake runner does not implement #{op}")
      end
    end

    def mismatch(container, session_id)
      error("session_mismatch", "the session container #{container.name} is not session #{session_id}'s")
    end

    def ok(fields = {})
      { "status" => "ok" }.merge(fields)
    end

    def error(klass, message)
      { "status" => "error", "error" => { "class" => klass, "message" => message } }
    end
  end

  # The one session container of a machine, as the host runner and the Docker
  # daemon see it, shared by FakeHostRunner and, in the runtime contract test,
  # by the fake Docker Engine DockerRuntime calls.
  class FakeMachine
    Container = Struct.new(:id, :name, :session_id, :payload, :running, :exit_code, :oom_killed, :files,
                           keyword_init: true)

    attr_reader :container, :images, :execs
    attr_accessor :key, :fail_writes

    def initialize(key: "aixle-env")
      @key = key
      @images = []
      @execs = []
      @on_exec = ->(_cmd) { [ "", "", 0 ] }
    end

    def on_exec(&block)
      @on_exec = block
    end

    def image?(payload) = images.include?(payload["image"])
    def pull(payload) = images << payload["image"]

    def start(session_id, payload = {}, name: "aixle-#{key}-#{session_id}")
      @container = Container.new(id: SecureRandom.hex(32), name: name, session_id: session_id, payload: payload,
                                 running: true, exit_code: nil, oom_killed: false, files: {})
    end

    def exit!(code, oom_killed: false)
      container.running = false
      container.exit_code = code
      container.oom_killed = oom_killed
    end

    def stop(session_id)
      return false unless container&.session_id == session_id

      @container = nil
      true
    end

    def reset
      removed = [ container&.name ].compact
      @container = nil
      removed
    end

    def exec(cmd)
      execs << cmd
      @on_exec.call(cmd)
    end

    def write(payload)
      return false if fail_writes

      container.files[payload.fetch("path")] = Base64.strict_decode64(payload.fetch("content"))
      true
    end
  end
end
