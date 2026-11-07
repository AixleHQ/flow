# frozen_string_literal: true

require "base64"

module ContainerRuntime
  # The runtime of a session on an external runner
  # (docs/design/agent-runtimes/DESIGN.md §1.3, §5.3): every BaseRuntime call
  # the strategy makes is one op on the session's machine's queue
  # (Runners::Operations), which the host runner executes against the
  # session's container (runner/protocol/PROTOCOL.md §6). The call waits for
  # the op's result and answers what DockerRuntime answers for the same call,
  # so the strategy code is the same on both.
  #
  # The phases:
  #
  # - pull_image takes a free machine of the session's runner
  #   (Runners::Machines; every machine busy is a CapacityError, so the session
  #   waits) and sends `image.ensure` with the image pinned by digest.
  # - create_container sends `container.start`: the container's environment,
  #   which carries the session's secrets, exists only in this phase
  #   (ContainerService::CREATE_ONLY_KEYS), and the runner creates and starts
  #   the container in one op, as a Kubernetes pod is created running.
  # - start_container and wait_for_ready wait for nothing more than the
  #   container running (`status`), as DockerRuntime#start_container does.
  # - cleanup_session sends `container.stop` and `env.reset`, and frees the
  #   machine once the reset succeeded.
  #
  # An op that ends `error` or `expired` gives the strategy what a hosted
  # failure gives: a container the runner does not find is unreachable
  # (ContainerUnreachableError from exec!, exit code 1 from exec, nil from
  # read_file, false from write_file, :missing from container_status).
  class RunnerRuntime < BaseRuntime
    # Error classes that mean the session's container is not there for this
    # session (PROTOCOL.md §6.3).
    GONE = %w[no_session_container session_mismatch].freeze
    # How long past an exec's own timeout its op stays open: coreutils
    # `timeout` sends SIGKILL 5 s after SIGTERM, and the runner reads the end
    # of the output after that.
    EXEC_GRACE = 30
    READY_TIMEOUT = 30
    READY_INTERVAL = 1
    # `container.resources.memory` is a Kubernetes quantity on every type (§2.7).
    MEMORY_UNITS = { "" => 1, "k" => 1000, "m" => 1000**2, "g" => 1000**3, "t" => 1000**4,
                     "ki" => 1024, "mi" => 1024**2, "gi" => 1024**3, "ti" => 1024**4 }.freeze

    # One op's outcome.
    Outcome = Data.define(:op, :state, :result) do
      def ok? = state == "completed"
      def expired? = state == "expired"
      def error_class = expired? ? "expired" : result&.dig("error", "class")
      def data = result&.fetch("data", nil) || {}

      def message
        return "#{op} expired: the runner did not answer before its deadline" if expired?

        "#{op} failed: #{error_class}: #{result&.dig('error', 'message')}"
      end
    end

    attr_reader :session

    # `op_timeout` caps every op's deadline, for a caller that reads many
    # sessions in turn (the scanners): a machine that does not answer then
    # costs it seconds, not a minute per call.
    def initialize(session, image_pin: Runners::ImagePin.new, op_timeout: nil)
      super()
      @session = session
      @image_pin = image_pin
      @op_timeout = op_timeout
    end

    # -- Identity and cleanup (AdmittedPhaseActivity) -------------------------

    # Persisted before the create, when no machine may be assigned yet, so it
    # names the session rather than its container.
    def session_identity(_session)
      "runner-session-#{session.id}"
    end

    # A session never given a machine has nothing to remove, and one that
    # released its machine has had its container stopped and the machine reset.
    # A machine the session still holds is not absent until the cleanup has run:
    # it still needs its reset. One whose reset failed is out of rotation, held
    # by the session until it is returned to service (task 11), and the
    # session's reservation does not wait for that.
    def session_absent?(_id)
      environment = machine
      environment.nil? || Runners::Machines.reset_failed?(environment)
    end

    # `container.stop`, then `env.reset`, which removes every container and the
    # workspace and cache volumes of the machine, so nothing of the session
    # reaches the next one (§7.2), and the machine is free again. A failed
    # reset, a machine that does not answer included, keeps the machine held
    # by this session, out of rotation, with the reason.
    def cleanup_session(_id)
      environment = machine
      return if environment.nil?

      stopped = call("container.stop", {}, lifecycle: true)
      Rails.logger.warn("[RunnerRuntime] session #{session.id}: #{stopped.message}") unless stopped.ok?

      reset = call("env.reset", {}, lifecycle: true, environment_op: true)
      return Runners::Machines.release!(environment, session) if reset.ok?

      Rails.logger.warn("[RunnerRuntime] session #{session.id}: #{reset.message}; machine #{environment.key} kept out")
      reason = reset.expired? ? "the runner did not answer" : "#{reset.error_class}: #{reset.result&.dig('error', 'message')}"
      Runners::Machines.hold_failed!(environment, session, reason)
    end

    # -- Lifecycle ------------------------------------------------------------

    def pull_image(image)
      raise ArgumentError, "image is required" if image.blank?

      Runners::Machines.acquire!(session)
      outcome = call("image.ensure", pin(image), lifecycle: true, environment_op: true)
      raise ImagePullError, "Could not pull #{image}: #{outcome.message}" unless outcome.ok?

      pulled = outcome.data["pulled"] == true
      { status: pulled ? :pulled : :cached, image: image, duration_seconds: outcome.data["duration_ms"].to_i / 1000 }
    end

    def create_container(spec)
      Runners::Machines.acquire!(session)
      outcome = call("container.start", container_payload(spec), lifecycle: true)
      return outcome.data["name"] if outcome.ok?
      # A create retried after an answer that never arrived finds its own
      # container running (SessionRuntimeOperation#replayable?).
      return container_name if outcome.error_class == "container_exists" && %i[running starting].include?(container_status(nil))

      raise RuntimeError, outcome.message
    end

    def start_container(id)
      id
    end

    def wait_for_ready(_id, _ports = [])
      deadline = Time.current + READY_TIMEOUT
      loop do
        status = container_status(nil)
        return true if status == :running
        raise "Container exited with code #{container_termination(nil)&.dig(:exit_code)}" if status == :terminated
        raise "Container is gone" if status == :missing
        raise "Container failed to start within #{READY_TIMEOUT}s" if Time.current > deadline

        sleep READY_INTERVAL
      end
    end

    def stop_container(_id, _timeout = nil, _options = {})
      outcome = call("container.stop", {}, lifecycle: true)
      raise RuntimeError, outcome.message unless outcome.ok?
    end

    def remove_container(id, _options = {})
      stop_container(id)
    end

    # -- Execution ------------------------------------------------------------

    def exec(id, cmd, opts = {})
      run_exec(id, cmd, opts, raise_on_gone: false)
    end

    def exec!(id, cmd, opts = {})
      run_exec(id, cmd, opts, raise_on_gone: true)
    end

    # -- File I/O -------------------------------------------------------------

    def write_file(_id, path, content, mode: 0o644, uid: 0, gid: 0)
      return false if path.blank?

      payload = { "path" => path.to_s, "content" => Base64.strict_encode64(content.to_s), "mode" => mode,
                  "uid" => uid.to_i, "gid" => gid.to_i }
      outcome = call("write_file", payload)
      Rails.logger.warn("[RunnerRuntime] write_file #{path}: #{outcome.message}") unless outcome.ok?
      outcome.ok?
    end

    def read_file(_id, path)
      return nil if path.blank?

      outcome = call("read_file", { "path" => path.to_s })
      unless outcome.ok?
        Rails.logger.debug { "[RunnerRuntime] read_file #{path}: #{outcome.message}" }
        return nil
      end

      Base64.strict_decode64(outcome.data["content"].to_s)
    rescue ArgumentError => e
      Rails.logger.warn("[RunnerRuntime] read_file #{path}: the runner sent content that is not base64: #{e.message}")
      nil
    end

    # -- Introspection --------------------------------------------------------

    # The session's container is the one `container.start` named after it; the
    # runner finds it by its labels, so the id is only a handle.
    def resolve_container(container_id)
      container_id.presence
    end

    def container_identifier(container)
      container.presence&.to_s
    end

    def container_status(_id)
      return :missing if machine_of_session.nil?

      outcome = call("status", {})
      return :missing if GONE.include?(outcome.error_class)
      return :unknown unless outcome.ok?

      { "running" => :running, "starting" => :starting, "terminated" => :terminated,
        "missing" => :missing }.fetch(outcome.data["state"], :unknown)
    end

    def container_termination(_id)
      return nil if machine_of_session.nil?

      outcome = call("status", {})
      return nil unless outcome.ok? && outcome.data["state"] == "terminated"

      { reason: ("OOMKilled" if outcome.data["oom_killed"]), exit_code: outcome.data["exit_code"]&.to_i }.compact
    end

    def wait_container(id, timeout = nil)
      deadline = Time.current + (timeout || 1800)
      loop do
        if container_status(id) == :terminated
          return { "StatusCode" => container_termination(id)&.dig(:exit_code) }
        end
        raise WaitTimeout, "still running after #{timeout || 1800}s" if Time.current >= deadline

        sleep READY_INTERVAL
      end
    end

    # The tail of the terminal output, which the image's entrypoint writes to
    # the container's stdout as well (PROTOCOL.md §6.3, `logs`).
    def container_logs(_id, stdout: true, **)
      outcome = stdout ? call("logs", {}) : nil
      { stdout: outcome&.ok? ? outcome.data["tail"].to_s : "", stderr: "" }
    end

    # -- Garbage collection ---------------------------------------------------

    # A runner session's objects are the runner's to remove, by label
    # (`env.scrub`, `env.reset`), not the hosted sweep's.
    def list_session_resources(*)
      []
    end

    def delete_session_resource(_resource)
      true
    end

    private

    attr_reader :image_pin

    def run_exec(_id, cmd, opts, raise_on_gone:)
      payload = { "cmd" => Array(cmd).map(&:to_s) }
      timeout = opts[:timeout].to_i
      payload["timeout"] = timeout if timeout.positive?
      payload["stdin"] = opts[:stdin] if opts[:stdin].is_a?(String)
      outcome = call("exec", payload, seconds: (timeout + EXEC_GRACE if timeout.positive?))

      if outcome.ok? || outcome.error_class == "exec_timeout"
        exit_code = outcome.result["exit_code"] || (outcome.ok? ? 0 : 124)
        return [ lines(outcome.result["stdout"]), lines(outcome.result["stderr"]), exit_code ]
      end
      if raise_on_gone && (GONE.include?(outcome.error_class) || outcome.expired? || machine_of_session.nil?)
        raise ContainerUnreachableError.new(outcome.message, container_identifier: container_name)
      end

      [ [], [ "#{outcome.message}\n" ], 1 ]
    end

    def lines(text)
      text.to_s.empty? ? [] : text.to_s.lines
    end

    # Sends one op to the session's machine and waits for its outcome. A
    # session op names the session in its envelope; an environment op names
    # none. Without a machine there is nobody to ask, and the op answers as a
    # container that is not there.
    def call(op, payload, lifecycle: false, environment_op: false, seconds: nil)
      environment = machine_of_session
      return Outcome.new(op: op, state: "failed", result: no_machine_result) if environment.nil?

      operation = Runners::Operations.enqueue!(environment, op: op, payload: payload,
                                                            deadline_at: deadline_at(seconds, lifecycle),
                                                            session: (session unless environment_op))
      operation = Runners::Operations.await(operation, on_wait: method(:heartbeat))
      Outcome.new(op: op, state: operation.state.to_s, result: operation.result)
    end

    def no_machine_result
      { "error" => { "class" => "no_session_container", "message" => "the session has no runner machine" } }
    end

    # The machine the session runs on. Ops of a session that already released
    # its machine still go there: the runner refuses them with
    # `session_mismatch` when the machine's container is another session's.
    def machine_of_session
      return nil if session.runner_environment_id.nil?

      @machine_of_session = nil if @machine_of_session&.id != session.runner_environment_id
      @machine_of_session ||= RunnerEnvironment.find_by(id: session.runner_environment_id)
    end

    # The machine while the session still holds it, read fresh: the hold is
    # what the cleanup changes.
    def machine
      RunnerEnvironment.find_by(current_session_id: session.id)
    end

    # An op's deadline is the activity's own end, so no op outlives the
    # activity that waits for it (§6.4), and within it the op's own budget.
    def deadline_at(seconds, lifecycle)
      seconds ||= lifecycle ? Settings.runners.lifecycle_op_timeout.to_i : Settings.runners.op_timeout.to_i
      seconds = [ seconds, @op_timeout ].min if @op_timeout
      [ Time.current + seconds, activity_deadline ].compact.min.change(usec: 0)
    end

    def activity_deadline
      return nil unless Temporalio::Activity::Context.exist?

      info = Temporalio::Activity::Context.current.info
      timeout = info.start_to_close_timeout.to_f
      info.started_time + timeout if timeout.positive? && info.started_time
    end

    def heartbeat
      Temporalio::Activity::Context.current.heartbeat if Temporalio::Activity::Context.exist?
    end

    def container_name
      environment = machine_of_session
      environment && "aixle-#{environment.key}-#{session.id}"
    end

    def pin(image)
      image_pin.call(image)
    rescue Runners::ImagePin::Error => e
      raise ImagePullError, "Could not pin #{image} to a digest: #{e.message}. " \
                            "The platform needs to reach the image's registry, or agents.images to pin it."
    end

    def container_payload(spec)
      container = Runners::ConfigSchema.value(runner_config, "container.image_override")
      image = container.presence || spec[:image]
      {
        **pin(image),
        "env" => env_hash(spec[:env_vars]),
        "workspace_volume" => setting("container.workspace_volume"),
        "mounts" => mounts,
        "network" => setting("container.network"),
        "pid" => setting("container.pid"),
        "resources" => resources(spec[:host_config] || {}),
        "privilege_escalation" => spec[:privilege_escalation] == true
      }
    end

    def env_hash(env_vars)
      Array(env_vars).each_with_object({}) do |entry, env|
        name, value = entry.to_s.split("=", 2)
        env[name] = value.to_s if name.present?
      end
    end

    def runner_config
      session.runner&.config || {}
    end

    def setting(path)
      Runners::ConfigSchema.value(runner_config, path)
    end

    # §2.7 `container.*` mounts as the `container.start` mounts of PROTOCOL.md §6.2.
    def mounts
      cache = Array(setting("container.cache_mounts")).map do |mount|
        if mount["name"].present?
          { "type" => "cache", "name" => mount["name"], "target" => mount["target"] }
        else
          { "type" => "bind", "source" => mount["host_path"], "target" => mount["target"], "writable" => true }
        end
      end
      home = setting("container.home_mount")
      home_mount = if home.is_a?(Hash) && home["path"].present?
        [ { "type" => "bind", "source" => home["path"], "target" => home["path"], "writable" => home["writable"] == true } ]
      end
      extra = Array(setting("container.extra_mounts")).map do |mount|
        { "type" => "bind", "source" => mount["source"], "target" => mount["target"], "writable" => mount["writable"] == true }
      end
      socket = if setting("container.docker_socket") && setting("container.allow_privileged_mounts")
        [ { "type" => "bind", "source" => "/var/run/docker.sock", "target" => "/var/run/docker.sock", "writable" => true } ]
      end
      cache + Array(home_mount) + extra + Array(socket)
    end

    # The hosted container's limits (AgentBaseStrategy#build_host_config), or
    # the runner's `container.resources` where it sets them.
    def resources(host_config)
      period = host_config["CpuPeriod"].to_f
      resources = {
        "cpus" => (period.positive? ? (host_config["CpuQuota"].to_f / period).round(2) : 0),
        "memory_bytes" => host_config["Memory"].to_i,
        "pids_limit" => host_config["PidsLimit"].to_i
      }
      configured = setting("container.resources") || {}
      resources["cpus"] = configured["cpus"] if configured["cpus"]
      resources["memory_bytes"] = memory_bytes(configured["memory"]) if configured["memory"]
      resources
    end

    # `4Gi`, `512M`.
    def memory_bytes(quantity)
      number, unit = quantity.to_s.match(/\A([0-9]+(?:\.[0-9]+)?)([a-zA-Z]*)\z/)&.captures
      return 0 if number.nil?

      (number.to_f * MEMORY_UNITS.fetch(unit.downcase, 1)).to_i
    end
  end
end
