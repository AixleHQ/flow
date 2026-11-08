# frozen_string_literal: true

require "base64"
require "temporalio/activity"

module ContainerRuntime
  # The runtime of a session on an external runner
  # (docs/design/agent-runtimes/DESIGN.md §1.3, §5.3): every BaseRuntime call
  # the strategy makes is one op on the session's machine's queue
  # (Runners::Operations), which the host runner executes against the
  # session's container (runner/protocol/PROTOCOL.md §6). The call waits for
  # the op's result and answers what DockerRuntime answers for the same call,
  # so the strategy code is the same on both.
  #
  # One object serves any session, as DockerRuntime does: each call finds its
  # session from its own argument. create_container reads it from the spec's
  # `aixle.session_id` label; every other call from the admission whose
  # `runtime_id` its container id or cleanup identity is (session_for), never
  # by parsing the string. ContainerRuntime.for_session decides between a
  # runner and hosted.
  #
  # The phases:
  #
  # - pull_image does nothing, as KubernetesRuntime#pull_image: the runner
  #   pulls the image in `container.start`.
  # - create_container takes a free machine of the session's runner, the first
  #   phase that needs one (Runners::Machines; every machine busy is a
  #   CapacityError, so the session waits), and sends `container.start` with
  #   the image reference as it was given, a tag or a digest: the runner always
  #   pulls it, then creates and starts the container in one op, as a
  #   Kubernetes pod is created running. The container's environment, which
  #   carries the session's secrets, exists only in this phase
  #   (ContainerService::CREATE_ONLY_KEYS). The admission's identity is
  #   persisted before this phase, so a failure or a stop in it, the pull
  #   included, still runs cleanup_session and frees the machine.
  # - start_container and wait_for_ready wait for nothing more than the
  #   container running (`status`), as DockerRuntime#start_container does.
  # - cleanup_session sends `container.stop` and `env.reset`, and frees the
  #   machine once the reset succeeded; a failed reset moves it to `failed`.
  #   It waits for nothing queued: while an earlier op of the session is
  #   unfinished on the machine (a `container.start` whose wait a stop cut
  #   short), cleanup_ready? is false, and the cleanup is retried until that op
  #   is answered or expired. Its deadline bounds the wait.
  #
  # A session's ops go to its machine only while the session holds it
  # (runner_environments.current_session_id): Runners::Operations.enqueue!
  # checks the hold under the machine's lock and creates nothing otherwise.
  # Once the session has released the machine, or never had one, every op
  # answers `no_session_container` here, so a late op of a finished session,
  # from a scanner or a sweep racing the cleanup, never reaches the next
  # session's machine, its `env.reset` included. The runner's own
  # `session_mismatch` check is the safety net on the machine.
  #
  # The wait for an op ends at its `deadline_at`, which is the activity's end
  # less ACTIVITY_MARGIN: the op is then expired here, and the strategy gets the
  # expired outcome before Temporal times the activity out.
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
    # How long before its activity's end an op's deadline falls: what is left
    # for the activity to act on an op that expired, a machine's reset that
    # failed for one.
    ACTIVITY_MARGIN = 5
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

    # `op_timeout` caps every op's deadline: it is the caller's budget, for a
    # caller that reads many sessions in turn (the scanners), so a machine that
    # does not answer costs it seconds, not a minute per call.
    def initialize(op_timeout: nil)
      super()
      @op_timeout = op_timeout
    end

    # -- Identity and cleanup (AdmittedPhaseActivity) -------------------------

    # Names the session rather than its container, so it is known before any
    # machine is assigned.
    def session_identity(session)
      "runner-session-#{session.id}"
    end

    # Absent once the session holds no machine: it never took one, its machine
    # was reset and is free again, or its reset failed and the machine is
    # `failed`, out of rotation.
    def session_absent?(id)
      session = session_for(id)
      session.nil? || machine(session).nil?
    end

    # False while an op of the session is still `pending` or `delivered` on
    # its machine: the runner runs a machine's ops one at a time, in order, so
    # a cleanup op would wait behind it and expire.
    def cleanup_ready?(id)
      session = session_for(id)
      environment = session && machine(session)
      return true if environment.nil?

      !RunnerOperation.deliverable.exists?(runner_environment_id: environment.id, terminal_session_id: session.id)
    end

    # `container.stop`, then `env.reset`, which removes every container and the
    # workspace and cache volumes of the machine, so nothing of the session
    # reaches the next one (§7.2), and the machine is free again. A failed
    # `container.stop` is logged, and the reset still runs. A failed reset, a
    # machine that does not answer included, moves the machine to `failed`
    # with the reason.
    def cleanup_session(id)
      session = session_for(id)
      environment = session && machine(session)
      return if environment.nil?

      stopped = call(session, "container.stop", {}, lifecycle: true)
      Rails.logger.warn("[RunnerRuntime] session #{session.id}: #{stopped.message}") unless stopped.ok?

      reset = call(session, "env.reset", {}, lifecycle: true)
      return Runners::Machines.release!(environment, session) if reset.ok?

      Rails.logger.warn("[RunnerRuntime] session #{session.id}: #{reset.message}; machine #{environment.key} is failed")
      reason = reset.expired? ? "the runner did not answer" : "#{reset.error_class}: #{reset.result&.dig('error', 'message')}"
      Runners::Machines.fail!(environment, "env.reset failed after session #{session.id}: #{reason}", holder: session)
    end

    # -- Lifecycle ------------------------------------------------------------

    # The runner pulls the image in `container.start` (create_container).
    def pull_image(image)
      raise ArgumentError, "image is required" if image.blank?

      Rails.logger.info("[RunnerRuntime] Pull image is a no-op: the runner pulls #{image} in container.start")
      { status: :skipped, image: image, duration_seconds: 0 }
    end

    # A refusal the runner answered is a CreateRefusedError: the runner created
    # nothing, or removed what it could not start (PROTOCOL.md §6.2), so the
    # create pins no reservation. An expired create stays uncertain.
    def create_container(spec)
      session = spec_session(spec)
      Runners::Machines.acquire!(session)
      payload = container_payload(session, spec)
      outcome = call(session, "container.start", payload, lifecycle: true)
      return outcome.data["name"] if outcome.ok?
      raise RuntimeError, outcome.message if outcome.expired?
      if outcome.error_class == "image_pull_failed"
        raise CreateRefusedError, "Could not pull #{payload['image']}: #{outcome.message}"
      end
      # A create retried after an answer that never arrived finds its own
      # container running (SessionRuntimeOperation#replayable?).
      if outcome.error_class == "container_exists" && %i[running starting].include?(status_of(session))
        return container_name(session)
      end

      raise CreateRefusedError, outcome.message
    end

    def start_container(id)
      id
    end

    def wait_for_ready(id, _ports = [])
      deadline = Time.current + READY_TIMEOUT
      loop do
        status = container_status(id)
        return true if status == :running
        raise "Container exited with code #{container_termination(id)&.dig(:exit_code)}" if status == :terminated
        raise "Container is gone" if status == :missing
        raise "Container failed to start within #{READY_TIMEOUT}s" if Time.current > deadline

        sleep READY_INTERVAL
      end
    end

    # A container that is already gone is stopped, as on Docker.
    def stop_container(id, _timeout = nil, _options = {})
      outcome = call(session_for(id), "container.stop", {}, lifecycle: true)
      raise RuntimeError, outcome.message unless outcome.ok? || outcome.error_class == "no_session_container"
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

    def write_file(id, path, content, mode: 0o644, uid: 0, gid: 0)
      return false if path.blank?

      payload = { "path" => path.to_s, "content" => Base64.strict_encode64(content.to_s), "mode" => mode,
                  "uid" => uid.to_i, "gid" => gid.to_i }
      outcome = call(session_for(id), "write_file", payload)
      Rails.logger.warn("[RunnerRuntime] write_file #{path}: #{outcome.message}") unless outcome.ok?
      outcome.ok?
    end

    def read_file(id, path)
      return nil if path.blank?

      outcome = call(session_for(id), "read_file", { "path" => path.to_s })
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

    def container_status(id)
      status_of(session_for(id))
    end

    def container_termination(id)
      outcome = call(session_for(id), "status", {})
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
    def container_logs(id, stdout: true, **)
      outcome = stdout ? call(session_for(id), "logs", {}) : nil
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

    def run_exec(id, cmd, opts, raise_on_gone:)
      session = session_for(id)
      payload = { "cmd" => Array(cmd).map(&:to_s) }
      timeout = opts[:timeout].to_i
      payload["timeout"] = timeout if timeout.positive?
      payload["stdin"] = opts[:stdin] if opts[:stdin].is_a?(String)
      outcome = call(session, "exec", payload, seconds: (timeout + EXEC_GRACE if timeout.positive?))

      if outcome.ok? || outcome.error_class == "exec_timeout"
        exit_code = outcome.result["exit_code"] || (outcome.ok? ? 0 : 124)
        return [ lines(outcome.result["stdout"]), lines(outcome.result["stderr"]), exit_code ]
      end
      if raise_on_gone && (GONE.include?(outcome.error_class) || outcome.expired?)
        raise ContainerUnreachableError.new(outcome.message, container_identifier: session && container_name(session))
      end

      [ [], [ "#{outcome.message}\n" ], 1 ]
    end

    def lines(text)
      text.to_s.empty? ? [] : text.to_s.lines
    end

    def status_of(session)
      outcome = call(session, "status", {})
      return :missing if GONE.include?(outcome.error_class)
      return :unknown unless outcome.ok?

      { "running" => :running, "starting" => :starting, "terminated" => :terminated,
        "missing" => :missing }.fetch(outcome.data["state"], :unknown)
    end

    # The session a container id or a cleanup identity is for: the session of
    # the admission whose `runtime_id` it is (AdmittedPhaseActivity writes the
    # identity before the create, and the container's name after it). Nil for
    # an id no runner admission has.
    def session_for(id)
      return nil if id.blank?

      session_id = SessionAdmission.where(runtime_kind: self.class.name, runtime_id: id.to_s).pick(:terminal_session_id)
      session_id && TerminalSession.find_by(id: session_id)
    end

    # The session a create is for: the spec's `aixle.session_id` label, which
    # AgentBaseStrategy#base_labels sets on every agent container.
    def spec_session(spec)
      labels = (spec[:labels] || {}).to_h.stringify_keys
      session_id = labels[DockerRuntime::SESSION_LABEL]
      raise ArgumentError, "the container spec has no #{DockerRuntime::SESSION_LABEL} label" if session_id.blank?

      TerminalSession.find(session_id)
    end

    # Sends one op to the session's machine and waits for its outcome, until
    # the op's deadline at most. A session op names the session in its
    # envelope; an environment op names none. A session that holds no machine,
    # or no session at all, has nobody to ask: the op answers as a container
    # that is not there, and nothing is enqueued. The hold read here is checked
    # again by the enqueue, under the machine's lock.
    def call(session, op, payload, lifecycle: false, seconds: nil)
      environment = session && machine(session)
      return Outcome.new(op: op, state: "failed", result: no_machine_result) if environment.nil?

      operation = Runners::Operations.enqueue!(environment, op: op, payload: payload,
                                                            deadline_at: deadline_at(seconds, lifecycle), session: session)
      return Outcome.new(op: op, state: "failed", result: no_machine_result) if operation.nil?

      operation = Runners::Operations.await(operation, on_wait: method(:on_wait))
      Outcome.new(op: op, state: operation.state.to_s, result: operation.result)
    end

    def no_machine_result
      { "error" => { "class" => "no_session_container", "message" => "the session holds no runner machine" } }
    end

    # The machine while the session holds it, read fresh for every op: the
    # hold is what the cleanup changes.
    def machine(session)
      Runners::Machines.held_by(session)
    end

    # An op's deadline is its own budget, and at most the activity's end less
    # ACTIVITY_MARGIN, so the wait for it ends before the activity does (§6.4).
    def deadline_at(seconds, lifecycle)
      seconds ||= lifecycle ? Settings.runners.lifecycle_op_timeout.to_i : Settings.runners.op_timeout.to_i
      seconds = [ seconds, @op_timeout ].min if @op_timeout
      [ Time.current + seconds, activity_deadline ].compact.min.change(usec: 0)
    end

    def activity_deadline
      return nil unless Temporalio::Activity::Context.exist?

      info = Temporalio::Activity::Context.current.info
      timeout = info.start_to_close_timeout.to_f
      info.started_time + timeout - ACTIVITY_MARGIN if timeout.positive? && info.started_time
    end

    # Runs between two looks at an op: the activity's heartbeat, and its
    # cancellation, as ToolStrategy#wait_with_heartbeat checks it, so a stopped
    # session stops waiting at once.
    def on_wait
      context = Temporalio::Activity::Context.current_or_nil
      return if context.nil?

      context.heartbeat
      context.cancellation.check!
    end

    # The name `container.start` gives the session's container, on the machine
    # the session holds.
    def container_name(session)
      environment = machine(session)
      environment && "aixle-#{environment.key}-#{session.id}"
    end

    # The image the runner pulls and starts: the runner's
    # `container.image_override` where it sets one, else the strategy's, as it
    # was given.
    def runner_image(config, image)
      setting(config, "container.image_override").presence || image
    end

    def container_payload(session, spec)
      config = session.runner&.config || {}
      {
        "image" => runner_image(config, spec[:image]),
        "env" => env_hash(spec[:env_vars]),
        "workspace_volume" => setting(config, "container.workspace_volume"),
        "mounts" => mounts(config),
        "network" => setting(config, "container.network"),
        "pid" => setting(config, "container.pid"),
        "resources" => resources(config, (spec[:host_config] || {}).stringify_keys),
        "privilege_escalation" => spec[:privilege_escalation] == true
      }
    end

    def env_hash(env_vars)
      Array(env_vars).each_with_object({}) do |entry, env|
        name, value = entry.to_s.split("=", 2)
        env[name] = value.to_s if name.present?
      end
    end

    def setting(config, path)
      Runners::ConfigSchema.value(config, path)
    end

    # §2.7 `container.*` mounts as the `container.start` mounts of PROTOCOL.md §6.2.
    def mounts(config)
      cache = Array(setting(config, "container.cache_mounts")).map do |mount|
        if mount["name"].present?
          { "type" => "cache", "name" => mount["name"], "target" => mount["target"] }
        else
          { "type" => "bind", "source" => mount["host_path"], "target" => mount["target"], "writable" => true }
        end
      end
      home = setting(config, "container.home_mount")
      home_mount = if home.is_a?(Hash) && home["path"].present?
        [ { "type" => "bind", "source" => home["path"], "target" => home["path"], "writable" => home["writable"] == true } ]
      end
      extra = Array(setting(config, "container.extra_mounts")).map do |mount|
        { "type" => "bind", "source" => mount["source"], "target" => mount["target"], "writable" => mount["writable"] == true }
      end
      socket = if setting(config, "container.docker_socket") && setting(config, "container.allow_privileged_mounts")
        [ { "type" => "bind", "source" => "/var/run/docker.sock", "target" => "/var/run/docker.sock", "writable" => true } ]
      end
      cache + Array(home_mount) + extra + Array(socket)
    end

    # The hosted container's limits (AgentBaseStrategy#build_host_config), or
    # the runner's `container.resources` where it sets them.
    def resources(config, host_config)
      period = host_config["CpuPeriod"].to_f
      resources = {
        "cpus" => (period.positive? ? (host_config["CpuQuota"].to_f / period).round(2) : 0),
        "memory_bytes" => host_config["Memory"].to_i,
        "pids_limit" => host_config["PidsLimit"].to_i
      }
      configured = setting(config, "container.resources") || {}
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
