# frozen_string_literal: true

require "kubeclient"
require "json"
require "ostruct"
require "securerandom"
require "shellwords"
require "stringio"
require "tempfile"
require "uri"
require "websocket-client-simple"

module ContainerRuntime
  # Implements BaseRuntime using Kubernetes Pods + Services + IngressRoutes.
  class KubernetesRuntime < BaseRuntime
    DEFAULT_SERVICE_PORTS = [ 7681, 4040 ].freeze
    # The read-only terminal (a second ttyd, `-R`, on a read-only tmux client)
    # that everyone but the session's owner is routed to.
    VIEW_PORT = 7682
    DEFAULT_CONTAINER_NAME = "main"
    DEFAULT_WORKSPACE_DIR = "/workspace"
    DEFAULT_TRAEFIK_PORTS = [ 7681, 4040, 8443 ].freeze
    READY_TIMEOUT = 30
    READY_INTERVAL = 1
    HANDSHAKE_STATUS_LINE = %r{\AHTTP/\d(?:\.\d)?\s+(\d{3})}

    RUNTIME_APP_LABEL = "aixle-runtime"
    # Per-session identity label, carrying the pod name (`terminal-<route_token>`
    # for agent sessions). Every object a session owns carries it, which is what
    # makes the set reapable as a unit — and its ABSENCE is what keeps
    # namespace-wide infrastructure (the shared `terminal-auth` middleware, the
    # network policies) out of the sweep.
    CONTAINER_LABEL = "aixle-container"

    # The four object kinds a session owns, in deletion order: routing first, so
    # traffic stops being aimed at a backend that is about to disappear, then the
    # Service, then whatever pod is left. #list_session_resources returns them in
    # this order and callers may delete front to back.
    SESSION_RESOURCE_KINDS = [
      [ "IngressRoute", "ingressroutes", :traefik ],
      [ "Middleware",   "middlewares",   :traefik ],
      [ "Service",      "services",      :core ],
      [ "Pod",          "pods",          :core ]
    ].freeze

    # Cluster-wide selector for "objects belonging to one agent session".
    # `aixle-container` is a presence check — every session object sets it, no
    # shared object does.
    SESSION_RESOURCE_SELECTOR = "app=#{RUNTIME_APP_LABEL},#{CONTAINER_LABEL}"

    # Headers Traefik takes from the ws_auth answer instead of the browser's
    # request. Cookie and Authorization are listed so the pod never receives the
    # viewer's Rails session: Traefik deletes every matching request header and
    # re-adds only what ws_auth returned (Api::V1::Internal::WsAuthController).
    TERMINAL_AUTH_RESPONSE_HEADERS_REGEX = "^(X-.*|Cookie|Authorization)$"
    # The one cookie the gate may hand the browser: the sandbox host's pass
    # (ContainerTicket), traded for the one-time ticket in a container URL.
    TERMINAL_AUTH_RESPONSE_COOKIES = [ ContainerTicket::COOKIE ].freeze

    # -- Lifecycle ------------------------------------------------------------

    def pull_image(image)
      raise ArgumentError, "image is required" if image.blank?

      Rails.logger.info("[KubernetesRuntime] Pull image is a no-op: #{image}")
      { status: :skipped, image: image, duration_seconds: 0 }
    end

    def session_identity(session)
      "#{namespace_for(project_id: session.project_id, user_id: session.user_id)}/terminal-#{session.route_token}"
    end

    def cleanup_session(id)
      handle = session_locator(id)
      session_objects(handle).each do |_kind, plural, client_key, object|
        metadata = object.metadata
        # UID precondition prevents deleting a replacement after the GET.
        kube_client(client_key).delete_entity(plural, metadata.name, handle.namespace,
          delete_options: { preconditions: { uid: metadata.uid } })
      rescue Kubeclient::ResourceNotFoundError
        next
      end
    end

    def session_absent?(id)
      session_objects(session_locator(id)).empty?
    end

    # Deleting and confirming absence need a namespace/name pair and nothing
    # else. #resolve_handle would additionally infer service ports, which costs
    # a Pod GET per call — on a path the reconciler walks every minute for every
    # unreleased reservation.
    def session_locator(id)
      return id if id.respond_to?(:pod_name) && id.respond_to?(:namespace)

      raw = id.to_s
      return resolve_handle(id) unless raw.match?(%r{\A[^/\s]+/[^/\s]+\z})

      namespace, pod_name = raw.split("/", 2)
      OpenStruct.new(pod_name: sanitize_name(pod_name), namespace: namespace)
    end

    def session_objects(handle)
      SESSION_RESOURCE_KINDS.flat_map do |kind, plural, client_key|
        raw = kube_client(client_key).get_entities(kind, plural, namespace: handle.namespace,
          label_selector: "app=#{RUNTIME_APP_LABEL},#{CONTAINER_LABEL}=#{handle.pod_name}", as: :raw)
        JSON.parse(raw.to_s).fetch("items").map do |item|
          [ kind, plural, client_key, Kubeclient::Resource.new(item) ]
        end
      end
    end

    def create_container(spec)
      handle = build_handle(spec)
      ensure_runtime_namespace_resources(handle, spec[:namespace_context])
      pod = build_pod(spec, handle)

      begin
        create_or_verify(core_client, "Pod", "pods", pod)
      rescue Kubeclient::HttpError => e
        if e.error_code.to_i == 403 && e.message.match?(/exceeded quota/i)
          raise CapacityError.new(e.message, reason: "namespace_quota")
        end
        raise
      end
      Rails.logger.info("[KubernetesRuntime] Pod created: #{handle.pod_name}")

      handle
    end

    def start_container(id)
      handle = resolve_handle(id)

      if handle.service_ports.any?
        create_service(handle)
        if handle.route_token.present?
          ensure_terminal_auth_middleware(handle.namespace)
          create_middlewares(handle)
          create_ingressroute(handle)
        end
      end

      handle
    end

    # -- Execution ------------------------------------------------------------

    def exec(id, cmd, opts = {})
      handle = resolve_handle(id)
      stdout, stderr, exit_code = exec_via_websocket(handle, cmd, opts)

      stdout_lines = stdout.empty? ? [] : stdout.split("\n").map { |line| "#{line}\n" }
      stderr_lines = stderr.empty? ? [] : stderr.split("\n").map { |line| "#{line}\n" }

      [ stdout_lines, stderr_lines, exit_code ]
    end

    # See BaseRuntime#exec!. A pod that no longer exists answers the exec
    # upgrade with a non-101 status (404 for a deleted pod); that surfaces as
    # ContainerUnreachableError instead of a generic [[], [], 1].
    def exec!(id, cmd, opts = {})
      exec(id, cmd, opts.merge(raise_on_unreachable: true))
    end

    # -- File I/O -------------------------------------------------------------

    def write_file(id, path, content, mode: 0o644, uid: 0, gid: 0)
      return false if path.blank?

      handle = resolve_handle(id)
      tar_io = build_tar_stream(path, content.to_s, mode: mode, uid: uid, gid: gid)
      cmd = [ "/bin/sh", "-c", "tar -xf - -C /" ]
      _stdout, _stderr, exit_code = exec_via_websocket(
        handle,
        cmd,
        stdin_io: tar_io,
        binary: true,
        close_stdin_on_eof: true
      )

      exit_code.to_i.zero?
    rescue StandardError => e
      Rails.logger.warn("[KubernetesRuntime] write_file failed for #{path}: #{e.message}")
      false
    ensure
      tar_io&.close!
    end

    def read_file(id, path)
      return nil if path.blank?

      tar_content = copy_from(id, path)
      return nil if tar_content.blank?

      extract_from_tar(tar_content, File.basename(path))
    rescue StandardError => e
      Rails.logger.warn("[KubernetesRuntime] read_file failed for #{path}: #{e.message}")
      nil
    end

    # -- Lifecycle (cont.) ----------------------------------------------------

    def stop_container(id, _timeout = nil, _options = {})
      handle = resolve_handle(id)
      core_client.delete_pod(handle.pod_name, handle.namespace)
    end

    def remove_container(id, _options = {})
      handle = resolve_handle(id)

      delete_ingressroute(handle)
      delete_middlewares(handle)
      delete_service(handle)
      delete_pod(handle)
    end

    def remove_image(_image)
      # No-op — images are managed by the Kubernetes node runtime.
    end

    def wait_for_ready(id, ports = [])
      handle = resolve_handle(id)
      wait_for_pod_ready(handle)

      verify_resources(handle, ports)

      if ports.present?
        wait_for_ports(handle, ports)
      end

      wait_for_traefik_route(handle) if handle.route_token.present?

      true
    end

    # -- Introspection --------------------------------------------------------

    def resolve_container(container_id)
      resolve_handle(container_id)
    end

    def container_identifier(container)
      return nil if container.blank?
      return container if container.is_a?(String)

      if container.respond_to?(:pod_name)
        namespace = container.respond_to?(:namespace) ? container.namespace : nil
        pod_name = container.pod_name
        return "#{namespace}/#{pod_name}" if namespace.present? && pod_name.present?
        return pod_name
      end

      if container.respond_to?(:id)
        id = container.id
        return id[0..11] if id.is_a?(String) && id.present?
      end

      container.to_s
    end

    # Pods are created with `restartPolicy: Never` (see #build_pod), so a container
    # that dies is NOT restarted: the pod leaves the Running phase and stays around
    # as Succeeded/Failed. When the node itself dies the pod object is eventually
    # garbage-collected instead and the lookup 404s. Both mean the agent is gone.
    #
    # Pending is deliberately :starting — a pod waiting on scheduling or an image
    # pull has simply not run yet.
    WAIT_POLL = 1

    # The main container's exit code once it has terminated. A pod that is gone
    # (stopped and deleted mid-wait) answers -1, the way a killed Docker
    # container reports no clean exit.
    def wait_container(id, timeout = nil)
      handle = resolve_handle(id)
      deadline = Time.current + (timeout || 1800)

      loop do
        code = terminated_exit_code(core_client.get_pod(handle.pod_name, handle.namespace), handle)
        return { "StatusCode" => code } unless code.nil?
        raise WaitTimeout, "still running after #{timeout}s" if Time.current >= deadline

        sleep(WAIT_POLL)
      end
    rescue Kubeclient::ResourceNotFoundError
      { "StatusCode" => -1 }
    end

    # Kubernetes keeps one stream per container; it cannot separate stderr, so
    # everything is reported as stdout.
    def container_logs(id, _opts = {})
      handle = resolve_handle(id)
      log = core_client.get_pod_log(handle.pod_name, handle.namespace,
                                    container: handle.container_name || DEFAULT_CONTAINER_NAME)
      { stdout: log.to_s, stderr: "" }
    rescue Kubeclient::ResourceNotFoundError
      { stdout: "", stderr: "" }
    end

    def container_status(id)
      handle = resolve_handle(id)
      pod = core_client.get_pod(handle.pod_name, handle.namespace)

      case pod&.status&.phase.to_s
      when "Running" then :running
      when "Pending" then :starting
      when "Succeeded", "Failed" then :terminated
      else :unknown
      end
    rescue Kubeclient::ResourceNotFoundError
      :missing
    rescue StandardError => e
      Rails.logger.warn("[KubernetesRuntime] container_status failed for #{id}: #{e.message}")
      :unknown
    end

    # -- Garbage collection ---------------------------------------------------

    # Every session-scoped object in the cluster, in deletion order.
    #
    # Cluster-wide on purpose: sessions live in per-project/per-user namespaces
    # (`aixle-prod-project-27`) whose set is not knowable from the database once
    # the owning rows are gone, so the label selector is the enumeration. This
    # needs list/delete on pods, services, ingressroutes and middlewares at
    # CLUSTER scope in the runtime's RBAC — the same ClusterRole that already
    # grants namespace creation.
    #
    # A listing failure is logged and answered with an empty list for that kind:
    # the sweeper's job is to delete garbage, and "I could not see" must never
    # be read as "there is none of it left alive".
    def list_session_resources(strict: false)
      SESSION_RESOURCE_KINDS.flat_map do |kind, plural, client_key|
        list_session_objects(kind, plural, client_key, strict: strict)
      end
    end

    def delete_session_resource(resource)
      return false if resource.blank? || resource.name.blank?

      entry = SESSION_RESOURCE_KINDS.find { |kind, _plural, _client| kind == resource.kind }
      return false if entry.nil?

      _kind, plural, client_key = entry
      kube_client(client_key).delete_entity(plural, resource.name, resource.namespace)
      true
    rescue Kubeclient::ResourceNotFoundError
      # Already gone — the goal state, not a failure.
      true
    rescue StandardError => e
      Rails.logger.warn("[KubernetesRuntime] Failed to delete #{resource}: #{e.message}")
      false
    end

    private

    def list_session_objects(kind, plural, client_key, strict: false)
      body = kube_client(client_key).get_entities(
        kind, plural,
        label_selector: SESSION_RESOURCE_SELECTOR,
        as: :raw
      )

      items = JSON.parse(body.to_s)["items"]
      Array(items).filter_map { |item| build_session_resource(kind, item) }
    rescue StandardError => e
      raise if strict
      Rails.logger.warn("[KubernetesRuntime] Failed to list #{kind} objects: #{e.message}")
      []
    end

    def build_session_resource(kind, item)
      metadata = item["metadata"] || {}
      name = metadata["name"]
      return nil if name.blank?

      pod_name = (metadata["labels"] || {})[CONTAINER_LABEL]

      SessionResource.new(
        kind: kind,
        name: name,
        namespace: metadata["namespace"],
        # nil for anything that is not an agent session (an internal-tool pod,
        # say). A nil token is an unprovable owner, and the sweeper keeps those.
        route_token: extract_route_token(pod_name),
        created_at: parse_kube_timestamp(metadata["creationTimestamp"])
      )
    end

    def parse_kube_timestamp(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def kube_client(client_key)
      client_key == :traefik ? traefik_client : core_client
    end

    def copy_from(id, path)
      return "" if path.blank?

      handle = resolve_handle(id)
      normalized = normalize_tar_path(path)
      return "" if normalized.blank?

      output = Tempfile.new("aixle-tar-read")
      output.binmode
      cmd = [ "/bin/sh", "-c", "tar -cf - -C / #{Shellwords.escape(normalized)}" ]
      _stdout, _stderr, exit_code = exec_via_websocket(handle, cmd, stdout_io: output, binary: true)

      return "" unless exit_code.to_i.zero?

      output.rewind
      output.read
    ensure
      output&.close!
    end

    def resolve_handle(id)
      return id if id.respond_to?(:pod_name) && id.respond_to?(:namespace)

      reference = extract_handle_reference(id)
      build_runtime_handle(
        pod_name: reference[:pod_name],
        namespace: reference[:namespace],
        route_token: reference[:route_token],
        service_ports: reference[:service_ports]
      )
    end

    def extract_handle_reference(id)
      if id.is_a?(Hash)
        pod_name = id[:pod_name] || id["pod_name"] || id[:id] || id["id"]
        namespace = id[:namespace] || id["namespace"]
        return build_handle_reference(pod_name, namespace: namespace, service_ports: id[:service_ports] || id["service_ports"])
      end

      if id.respond_to?(:pod_name)
        namespace = id.respond_to?(:namespace) ? id.namespace : nil
        service_ports = id.respond_to?(:service_ports) ? id.service_ports : nil
        return build_handle_reference(id.pod_name, namespace: namespace, service_ports: service_ports)
      end

      raw = id.to_s
      pod_name = raw[/pod_name=\"([^\"]+)\"/, 1] || raw
      namespace = raw[/namespace=\"([^\"]+)\"/, 1]

      if namespace.blank? && raw.match?(%r{\A[^/\s]+/[^/\s]+\z})
        namespace, pod_name = raw.split("/", 2)
      end

      build_handle_reference(pod_name, namespace: namespace)
    end

    def build_handle_reference(identifier, namespace: nil, service_ports: nil)
      pod_name = sanitize_name(identifier)
      route_token = extract_route_token(pod_name)

      {
        pod_name: pod_name,
        namespace: namespace.presence || runtime_namespace,
        route_token: route_token,
        service_ports: Array(service_ports).presence || infer_service_ports(pod_name, namespace, route_token)
      }
    end

    def infer_service_ports(pod_name, namespace, route_token)
      ports = pod_service_ports(pod_name, namespace)
      return ports if ports.any?

      route_token.present? ? DEFAULT_SERVICE_PORTS : []
    end

    def pod_service_ports(pod_name, namespace)
      pod = core_client.get_pod(pod_name, namespace.presence || runtime_namespace)
      containers = pod&.spec&.containers || []
      container = containers.find { |c| c.name == DEFAULT_CONTAINER_NAME } || containers.first
      return [] unless container.respond_to?(:ports)

      Array(container.ports).map { |port| port.containerPort.to_i }.select(&:positive?).uniq
    rescue StandardError
      []
    end

    def build_handle(spec)
      container_name = spec[:container_name]
      route_token = extract_route_token(container_name)
      pod_name = sanitize_name(container_name || "aixle-#{SecureRandom.hex(6)}")
      service_ports = extract_ports(spec[:exposed_ports])
      namespace = namespace_for(spec[:namespace_context])

      build_runtime_handle(
        pod_name: pod_name,
        namespace: namespace,
        route_token: route_token,
        service_ports: service_ports
      )
    end

    def build_runtime_handle(pod_name:, namespace:, route_token:, service_ports:)
      OpenStruct.new(
        pod_name: pod_name,
        namespace: namespace.presence || runtime_namespace,
        container_name: DEFAULT_CONTAINER_NAME,
        service_name: pod_name,
        ingress_name: "#{pod_name}-ingress",
        middleware_names: [ "#{pod_name}-tty-strip", "#{pod_name}-fs-strip", "#{pod_name}-view-strip" ],
        route_token: route_token,
        service_ports: service_ports
      )
    end

    def build_pod(spec, handle)
      env_vars = build_env_vars(spec[:env_vars])

      container = {
        name: handle.container_name,
        image: spec[:image],
        imagePullPolicy: image_pull_policy_for(spec[:image]),
        env: env_vars,
        command: spec[:cmd],
        workingDir: spec[:working_dir],
        resources: container_resources(spec),
        securityContext: agent_security_context
      }

      ports = handle.service_ports
      container[:ports] = ports.map { |port| { containerPort: port } } if ports.any?

      labels = session_labels(handle)
      pod_spec = {
        automountServiceAccountToken: false,
        enableServiceLinks: false,
        restartPolicy: "Never",
        containers: [ container ]
      }

      configured_pull_secrets = agents_image_pull_secrets
      if configured_pull_secrets.any?
        pod_spec[:imagePullSecrets] = configured_pull_secrets.map { |name| { name: name } }
      end

      apply_agents_node_pool(pod_spec, handle)

      Kubeclient::Resource.new(
        apiVersion: "v1",
        kind: "Pod",
        metadata: {
          name: handle.pod_name,
          namespace: handle.namespace,
          labels: labels
        },
        spec: pod_spec
      )
    end

    def create_or_verify(client, kind, plural, resource)
      case kind
      when "Service" then client.create_service(resource)
      when "Pod" then client.create_pod(resource)
      else client.create_entity(kind, plural, resource)
      end
    rescue Kubeclient::HttpError => e
      raise unless e.error_code.to_i == 409
      existing = client.get_entity(plural, resource.metadata.name, resource.metadata.namespace)
      raise "Runtime resource identity conflict" unless existing.metadata.labels.to_h == resource.metadata.labels.to_h
      if kind == "Pod" && existing.spec.containers.map(&:image) != resource.spec.containers.map(&:image)
        raise "Runtime image identity conflict"
      end
      existing
    end

    def create_service(handle)
      ports = handle.service_ports.map do |port|
        {
          name: "port-#{port}",
          port: port,
          targetPort: port,
          protocol: "TCP"
        }
      end

      service = Kubeclient::Resource.new(
        apiVersion: "v1",
        kind: "Service",
        metadata: {
          name: handle.service_name,
          namespace: handle.namespace,
          labels: session_labels(handle)
        },
        spec: {
          # Deliberately narrower than the metadata labels: the selector must
          # keep matching pods created by older builds, so it stays the two
          # identity labels and never grows.
          selector: pod_selector_labels(handle),
          ports: ports
        }
      )

      create_or_verify(core_client, "Service", "services", service)
      Rails.logger.info("[KubernetesRuntime] Service created: #{handle.service_name}")
    end

    def create_middlewares(handle)
      return if handle.route_token.blank?

      %w[tty fs view].each do |surface|
        strip = build_strip_middleware(handle, surface, "/t/#{handle.route_token}/#{surface}")
        create_or_verify(traefik_client, "Middleware", "middlewares", strip)
      end
    end

    def create_ingressroute(handle)
      ingress = Kubeclient::Resource.new(
        apiVersion: "traefik.io/v1alpha1",
        kind: "IngressRoute",
        metadata: {
          name: handle.ingress_name,
          namespace: handle.namespace,
          labels: session_labels(handle)
        },
        spec: {
          entryPoints: [ traefik_entrypoint ],
          tls: {},
          routes: [
            build_route(handle, "tty", 7681, [ traefik_auth_middleware, "#{handle.pod_name}-tty-strip" ]),
            build_route(handle, "fs", 4040, [ traefik_auth_middleware, "#{handle.pod_name}-fs-strip" ]),
            build_route(handle, "ide", 8443, [ traefik_auth_middleware ]),
            build_route(handle, "view", VIEW_PORT, [ traefik_auth_middleware, "#{handle.pod_name}-view-strip" ])
          ]
        }
      )

      create_or_verify(traefik_client, "IngressRoute", "ingressroutes", ingress)
      Rails.logger.info("[KubernetesRuntime] IngressRoute created: #{handle.ingress_name}")
    end

    def delete_ingressroute(handle)
      traefik_client.delete_entity("ingressroutes", handle.ingress_name, handle.namespace)
    end

    # A session created before one of these existed simply does not have it.
    def delete_middlewares(handle)
      handle.middleware_names.each do |name|
        traefik_client.delete_entity("middlewares", name, handle.namespace)
      rescue Kubeclient::ResourceNotFoundError
        next
      end
    end

    def delete_service(handle)
      core_client.delete_service(handle.service_name, handle.namespace)
    end

    def delete_pod(handle)
      core_client.delete_pod(handle.pod_name, handle.namespace)
    end

    def wait_for_pod_ready(handle)
      start_time = Time.current
      timeout = ready_timeout

      loop do
        pod = core_client.get_pod(handle.pod_name, handle.namespace)
        return true if pod_ready?(pod)

        elapsed = Time.current - start_time
        if elapsed > timeout
          conditions = Array(pod.status&.conditions)
          if conditions.any? { |c| c.type == "PodScheduled" && c.reason == "Unschedulable" }
            raise CapacityError, "Waiting for cluster capacity"
          end
          raise "Pod failed to start within #{timeout}s"
        end

        sleep ready_interval
      end
    end

    def pod_ready?(pod)
      return false unless pod&.status

      return false unless pod.status.phase == "Running"

      conditions = pod.status.conditions || []
      ready = conditions.find { |c| c.type == "Ready" }
      ready&.status == "True"
    end

    def port_open?(handle, port)
      hex_port = port.to_s(16).upcase.rjust(4, "0")
      cmd = [ "sh", "-c", "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -q ':#{hex_port} ' && echo 'open'" ]
      stdout_lines, _stderr_lines, exit_code = exec(handle, cmd)
      exit_code.to_i.zero? && stdout_lines.join.include?("open")
    end

    def exec_via_websocket(handle, cmd, opts)
      params = build_exec_params(handle, cmd, opts)
      url = build_exec_url(handle, params)
      headers = websocket_headers(close_stdin: opts[:close_stdin_on_eof])
      timeout = opts[:timeout].to_i
      timeout = 30 if timeout <= 0

      stdout_io = opts[:stdout_io]
      stderr_io = opts[:stderr_io]
      stdin_io = opts[:stdin_io]
      binary = opts[:binary]
      close_stdin_on_eof = opts[:close_stdin_on_eof]

      stdout = +""
      stderr = +""
      exit_code = 0
      done = false
      error = nil
      error_reported = false
      unreachable = nil
      mutex = Mutex.new
      cv = ConditionVariable.new
      ws_state = { closed: false }
      runtime = self

      exit_code_parser = method(:exit_code_from_status_payload)

      # Register the callbacks inside the connect block: the gem yields the
      # client *before* it opens the socket and starts its reader thread.
      # Registering them on the returned client instead is a race the API server
      # wins whenever it answers fast — the :error/:close events then land on a
      # client with no listeners and the exec sits until its timeout expires.
      ws = WebSocket::Client::Simple.connect(url.to_s, headers: headers) do |client|
        client.on(:open) do
          next unless stdin_io

          Thread.new do
            begin
              stdin_io.rewind if stdin_io.respond_to?(:rewind)
              while (chunk = stdin_io.read(16_384))
                break if runtime.send(:websocket_closed?, client, ws_state)
                client.send([ 0 ].pack("C") + chunk)
              end
              if close_stdin_on_eof && !runtime.send(:websocket_closed?, client, ws_state)
                # Kubernetes exec protocol v5 can close an individual stream
                # without tearing down the websocket. Channel 255 is the
                # stream-close control channel; its payload names stdin (0).
                # Keep reading after this frame so the process can finish and
                # channel 3 can report its real exit status.
                client.send([ 255, 0 ].pack("C*"))
              end
            rescue StandardError => e
              mutex.synchronize do
                error = e
                exit_code = 1
                done = true
                cv.broadcast
              end
            end
          end
        end

        client.on(:message) do |msg|
          next if msg.data.to_s.empty?

          data = msg.data.bytes
          channel = data.shift
          payload = data.pack("C*")
          payload.force_encoding("utf-8") unless binary

          case channel
          when 1
            if stdout_io
              stdout_io.write(payload)
            else
              stdout << payload
            end
          when 2
            if stderr_io
              stderr_io.write(payload)
            else
              stderr << payload
            end
          when 3
            mutex.synchronize do
              exit_code = exit_code_parser.call(payload)
              done = true
              cv.broadcast
            end
          end
        end

        # websocket-client-simple re-raises a failed handshake once per byte
        # still sitting in the HTTP response, so a single 404 from a deleted pod
        # emitted ~100 :error events — all of them logged, all of them redoing
        # the same bookkeeping. Handle only the first and tear the connection
        # down from inside the callback so the reader loop stops immediately.
        client.on(:error) do |msg|
          first_error = mutex.synchronize do
            if error_reported || runtime.send(:websocket_closed?, client, ws_state)
              false
            else
              error_reported = true
              error = msg
              exit_code = 1
              done = true
              unreachable = runtime.send(:build_unreachable_error, handle, client) if runtime.send(:handshake_error?, msg)
              cv.broadcast
              true
            end
          end
          next unless first_error

          if unreachable
            Rails.logger.warn("[KubernetesRuntime] WebSocket handshake failed: #{unreachable.message}")
          else
            Rails.logger.warn("[KubernetesRuntime] WebSocket error: #{msg.inspect}")
          end

          # #close runs on this (reader) thread and ends in Thread.kill(self),
          # so nothing may follow it here — and the mutex must already be
          # released, because closing emits :close, whose handler takes it.
          begin
            client.close
          rescue StandardError
            nil
          end
        end

        client.on(:close) do |_msg|
          mutex.synchronize do
            ws_state[:closed] = true
            done = true
            cv.broadcast
          end
        end
      end

      mutex.synchronize do
        cv.wait(mutex, timeout) unless done
        unless done
          exit_code = 1
          error = "exec timeout after #{timeout}s"
        end
      end

      begin
        ws.close if !websocket_closed?(ws, ws_state)
      rescue StandardError => e
        Rails.logger.warn("[KubernetesRuntime] Failed to close WebSocket: #{e.message}")
      end

      if unreachable
        raise unreachable
      elsif error.is_a?(StandardError)
        raise error
      elsif error
        Rails.logger.warn("[KubernetesRuntime] Exec error: #{error}")
      end

      [ stdout, stderr, exit_code ]
    rescue StandardError => e
      # Tearing the connection down from the reader thread can also break a
      # write still in flight on this one (IOError: stream closed in another
      # thread). The callback already recorded — and logged — the real cause, so
      # report that and stay quiet about the fallout.
      unreachable ||= e if e.is_a?(ContainerUnreachableError)

      if unreachable
        raise unreachable if opts[:raise_on_unreachable]
      else
        Rails.logger.warn("[KubernetesRuntime] Exec failed: #{e.message}")
      end

      [ "", "", 1 ]
    end

    def handshake_error?(error)
      error.is_a?(::WebSocket::Error::Handshake)
    end

    def build_unreachable_error(handle, ws)
      handshake = ws.respond_to?(:handshake) ? ws.handshake : nil

      ContainerUnreachableError.new(
        status_code: handshake_status_code(handshake),
        container_identifier: "#{handle.namespace}/#{handle.pod_name}"
      )
    end

    # websocket-client-simple hands us a bare
    # WebSocket::Error::Handshake::InvalidStatusCode with no status attached,
    # and WebSocket::Handshake::Client raises out of #<< before it records the
    # response (its #headers still hold *our* request headers). The raw response
    # text it accumulated is the only place the status survives, so read it
    # defensively and fall back to "no status" rather than fighting the gem.
    def handshake_status_code(handshake)
      return nil if handshake.nil?

      raw = handshake.instance_variable_get(:@data).to_s
      raw[HANDSHAKE_STATUS_LINE, 1]&.to_i
    rescue StandardError
      nil
    end

    def build_exec_params(handle, cmd, opts)
      params = {
        stdin: false,
        stdout: true,
        stderr: true,
        tty: false
      }
      params[:stdin] = true if opts[:stdin_io] || opts[:stdin]
      params[:container] = handle.container_name if handle.container_name.present?

      command = build_exec_command(cmd, params[:tty])
      params[:command] = command

      params
    end

    def exit_code_from_status_payload(payload)
      status = JSON.parse(payload)
      return 0 if status.is_a?(Hash) && status["status"] == "Success"

      causes = status.is_a?(Hash) ? status.dig("details", "causes") : nil
      exit_cause = Array(causes).find { |cause| cause["reason"] == "ExitCode" }
      code = exit_cause && exit_cause["message"].to_s
      return code.to_i if code.match?(/\A-?\d+\z/)

      1
    rescue JSON::ParserError
      1
    end

    def websocket_open?(ws)
      return false if ws.nil?
      return ws.open? if ws.respond_to?(:open?)
      return ws.state.to_s == "open" if ws.respond_to?(:state)

      false
    rescue StandardError
      false
    end

    def websocket_closed?(ws, ws_state)
      ws_state[:closed] || !websocket_open?(ws)
    end

    def build_exec_command(cmd, _tty)
      if cmd.is_a?(String)
        [ "/bin/sh", "-c", cmd ]
      elsif cmd.is_a?(Array) && cmd.size == 1
        [ "/bin/sh", "-c", cmd.first.to_s ]
      else
        Array(cmd)
      end
    end

    def build_exec_url(handle, params)
      ns = core_client.send(:build_namespace_prefix, handle.namespace)
      url = URI.parse(core_client.send(:rest_client)["#{ns}pods/#{handle.pod_name}/exec"].url)
      commands = params.delete(:command).map { |value| "command=#{URI.encode_www_form_component(value)}" }
      query = params.map { |key, value| "#{key}=#{value}" }
      url.query = (query + commands).join("&")
      url
    end

    def websocket_headers(close_stdin: false)
      headers = core_client.instance_variable_get(:@headers) || {}
      protocol = close_stdin ? "v5.channel.k8s.io" : "v4.channel.k8s.io"
      headers.merge("Sec-WebSocket-Protocol" => protocol)
    end

    def build_env_vars(env_vars)
      (env_vars || []).filter_map do |pair|
        next if pair.blank?

        key, value = pair.split("=", 2)
        next if key.blank?

        { name: key, value: value.to_s }
      end
    end

    def extract_ports(exposed_ports)
      return [] if exposed_ports.blank?

      exposed_ports.keys.map { |key| key.to_s.split("/").first.to_i }.select(&:positive?)
    end

    def extract_route_token(container_name)
      return nil if container_name.blank?
      return nil unless container_name.start_with?("terminal-")

      container_name.delete_prefix("terminal-")
    end

    def sanitize_name(name)
      sanitized = name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
      sanitized = sanitized.gsub(/-+/, "-").gsub(/\A-|-$\z/, "")
      sanitized = "aixle" if sanitized.empty?
      sanitized[0, 63]
    end

    def build_strip_middleware(handle, suffix, prefix)
      Kubeclient::Resource.new(
        apiVersion: "traefik.io/v1alpha1",
        kind: "Middleware",
        metadata: {
          name: "#{handle.pod_name}-#{suffix}-strip",
          namespace: handle.namespace,
          labels: session_labels(handle)
        },
        spec: {
          stripPrefix: {
            prefixes: [ prefix ]
          }
        }
      )
    end

    def build_terminal_auth_middleware(namespace = traefik_namespace)
      Kubeclient::Resource.new(
        apiVersion: "traefik.io/v1alpha1",
        kind: "Middleware",
        metadata: {
          name: traefik_auth_middleware,
          namespace: namespace,
          labels: resource_labels(namespace: namespace)
        },
        spec: {
          forwardAuth: {
            address: "#{internal_service_url('web', 4000)}/api/v1/internal/ws_auth",
            trustForwardHeader: true,
            authResponseHeadersRegex: TERMINAL_AUTH_RESPONSE_HEADERS_REGEX,
            addAuthCookiesToResponse: TERMINAL_AUTH_RESPONSE_COOKIES
          }
        }
      )
    end

    def build_route(handle, suffix, port, middlewares)
      service = {
        name: handle.service_name,
        namespace: handle.namespace,
        port: port
      }

      {
        match: build_route_match(handle, suffix),
        kind: "Rule",
        middlewares: middlewares.map { |name| { name: name } },
        services: [ service ]
      }
    end

    def build_route_match(handle, suffix)
      path_match = "PathPrefix(`/t/#{handle.route_token}/#{suffix}`)"
      host = route_domain_host
      return path_match if host.blank?

      "Host(`#{host}`) && #{path_match}"
    end

    # The host containers are served from — TRAEFIK_HTTP_BASE's, which is the
    # app's own unless a sandbox host of their own is configured (ContainerTicket).
    def route_domain_host
      ContainerTicket.sandbox_host.presence || Settings.domain.to_s.strip.presence
    end

    def traefik_entrypoint
      kube_setting(:traefik_entrypoint)
    end

    def traefik_auth_middleware
      kube_setting(:traefik_auth_middleware)
    end

    def runtime_namespace
      kube_setting(:namespace)
    end

    def traefik_namespace
      runtime_namespace
    end

    def resource_labels(namespace:)
      {
        "aixle.com/runtime-origin" => runtime_namespace,
        "aixle.com/runtime-namespace" => namespace
      }
    end

    # The identity every object of one session carries. Applied uniformly to the
    # Pod, the Service, the IngressRoute and both strip Middlewares so the whole
    # set can be found (and reaped) from the pod name alone — before this was
    # uniform, only pods were labelled and a dead node's Service/IngressRoute
    # could not be attributed to anything.
    def session_labels(handle)
      resource_labels(namespace: handle.namespace).merge(pod_selector_labels(handle))
    end

    def pod_selector_labels(handle)
      {
        "app" => RUNTIME_APP_LABEL,
        CONTAINER_LABEL => handle.pod_name
      }
    end

    def namespace_for(context)
      context = (context || {}).with_indifferent_access

      if context[:project_id].present?
        return sanitize_name("#{runtime_namespace}-project-#{context[:project_id]}")
      end

      if context[:user_id].present?
        return sanitize_name("#{runtime_namespace}-user-#{context[:user_id]}")
      end

      runtime_namespace
    end

    def isolated_runtime_namespace?(namespace)
      namespace.present? && namespace != runtime_namespace
    end

    def workspace_dir
      kube_setting(:workspace_dir)
    end

    def image_pull_policy
      kube_setting(:image_pull_policy)
    end

    # A moving tag (none, or `latest`) under IfNotPresent runs whichever copy a
    # node happened to cache — a fleet of mixed CLI versions. Such an image is
    # pulled every time; a pinned tag or a digest keeps the configured policy.
    def image_pull_policy_for(image)
      reference = image.to_s
      return image_pull_policy if reference.include?("@sha256:")

      tag = reference.split("/").last.to_s.split(":", 2)[1]
      tag.blank? || tag == "latest" ? "Always" : image_pull_policy
    end

    # Always: no privilege escalation (setuid, sudo) and no raw sockets. The full
    # restricted profile additionally needs every agent image to run as a non-root
    # user, so it is switched on per deployment once those images are rolled out.
    def agent_security_context
      if kube_setting(:restricted_agent_pods).to_s == "true"
        { runAsNonRoot: true, allowPrivilegeEscalation: false,
          capabilities: { drop: [ "ALL" ] }, seccompProfile: { type: "RuntimeDefault" } }
      else
        { allowPrivilegeEscalation: false, capabilities: { drop: [ "NET_RAW" ] } }
      end
    end

    # A tool run is sized by its host_config limits, as it is on Docker — requests
    # equal to the limits, since a short sandboxed run should get what it asks
    # for and nothing more. Agent pods keep the deployment's runtime sizing.
    # (Docker's PidsLimit has no per-container counterpart in a pod spec.)
    def container_resources(spec)
      host = spec[:host_config] || {}
      return runtime_container_resources unless (spec[:labels] || {})["aixle.type"] == "tool_execution"

      memory = host["Memory"].to_i
      quota = host["CpuQuota"].to_i
      return runtime_container_resources unless memory.positive? && quota.positive?

      millicores = (quota.to_f / (host["CpuPeriod"] || 100_000).to_f * 1000).ceil
      sized = { cpu: "#{millicores}m", memory: memory.to_s }
      { requests: sized, limits: sized }
    end

    def terminated_exit_code(pod, handle)
      statuses = Array(pod&.status&.containerStatuses)
      name = handle.container_name || DEFAULT_CONTAINER_NAME
      main = statuses.find { |status| status.name == name } || statuses.first
      terminated = main&.state&.terminated
      return terminated.exitCode.to_i if terminated

      case pod&.status&.phase.to_s
      when "Succeeded" then 0
      when "Failed" then -1
      end
    end

    def runtime_container_resources
      {
        requests: {
          cpu: kube_setting(:runtime_requests_cpu).to_s,
          memory: kube_setting(:runtime_requests_memory).to_s
        },
        limits: {
          cpu: kube_setting(:runtime_limits_cpu).to_s,
          memory: kube_setting(:runtime_limits_memory).to_s
        }
      }
    end

    def agents_image_pull_secrets
      raw = kube_setting(:agents_image_pull_secrets)

      values = case raw
      when String
        raw.split(",")
      when Array
        raw
      else
        Array(raw)
      end

      values.map(&:to_s).map(&:strip).reject(&:blank?).uniq
    end

    # Pins agent session pods to the dedicated agent node group, when one is
    # configured (`kubernetes.agents_node_pool`, see config/settings.yml for the
    # value format). Agent pods only: `route_token` is present exactly for the
    # `terminal-*` containers an agent session creates, so internal-tool and
    # custom-tool pods keep scheduling on the general pool.
    #
    # Nothing configured => neither key is written, and the pod spec stays byte
    # for byte what it was before this existed. That default is load-bearing: an
    # empty `nodeSelector`/`tolerations` pair, or one naming a node group that
    # does not exist yet, leaves every agent pod Pending.
    def apply_agents_node_pool(pod_spec, handle)
      return if handle.route_token.blank?

      entries = agents_node_pool_entries
      return if entries.empty?

      pod_spec[:nodeSelector] = entries.to_h { |entry| [ entry[:key], entry[:value] ] }
      pod_spec[:tolerations] = entries.map do |entry|
        {
          key: entry[:key],
          operator: "Equal",
          value: entry[:value],
          effect: entry[:effect]
        }
      end
    end

    # Parses `key=value[:Effect]` entries into the node label / taint toleration
    # pairs above. One entry drives both sides, so the selector and the
    # toleration can never drift apart. Unparseable entries are dropped rather
    # than raised on: a typo in a ConfigMap must not take agent scheduling down.
    def agents_node_pool_entries
      raw = kube_setting(:agents_node_pool)
      values = raw.is_a?(Array) ? raw : raw.to_s.split(",")

      values.filter_map do |value|
        entry = value.to_s.strip
        next if entry.blank?

        selector, effect = entry.split(":", 2)
        label_key, label_value = selector.to_s.split("=", 2)
        next if label_key.blank? || label_value.blank?

        {
          key: label_key.strip,
          value: label_value.strip,
          effect: effect.to_s.strip.presence || "NoSchedule"
        }
      end
    end

    def service_account_token_path
      kube_setting(:service_account_token_path)
    end

    def service_account_ca_path
      kube_setting(:service_account_ca_path)
    end

    def kubeconfig_path
      kube_setting(:kubeconfig_path)
    end

    def core_client
      @core_client ||= Kubeclient::Client.new(
        kube_endpoint,
        "v1",
        ssl_options: kube_ssl_options,
        auth_options: kube_auth_options
      )
    end

    def traefik_client
      return @traefik_client if defined?(@traefik_client)

      client = Kubeclient::Client.new(
        traefik_api_endpoint,
        "v1alpha1",
        ssl_options: kube_ssl_options,
        auth_options: kube_auth_options
      )

      begin
        client.discover unless client.discovered
      end

      @traefik_client = client
    end

    def networking_client
      return @networking_client if defined?(@networking_client)

      client = Kubeclient::Client.new(
        "#{kube_endpoint}/apis/networking.k8s.io",
        "v1",
        ssl_options: kube_ssl_options,
        auth_options: kube_auth_options
      )

      begin
        client.discover unless client.discovered
      end

      @networking_client = client
    end

    def traefik_api_endpoint
      "#{kube_endpoint}/apis/traefik.io"
    end

    def kube_endpoint
      return @kube_endpoint if defined?(@kube_endpoint)

      if in_cluster?
        host = kube_setting(:service_host)
        port = kube_setting(:service_port)
        @kube_endpoint = "https://#{host}:#{port}"
      else
        config = kube_config
        @kube_endpoint = config.context.api_endpoint
      end
    end

    def kube_ssl_options
      return @kube_ssl_options if defined?(@kube_ssl_options)

      if in_cluster?
        @kube_ssl_options = { ca_file: service_account_ca_path }
      else
        config = kube_config
        @kube_ssl_options = config.context.ssl_options
      end
    end

    def kube_auth_options
      return @kube_auth_options if defined?(@kube_auth_options)

      if in_cluster?
        @kube_auth_options = { bearer_token_file: service_account_token_path }
      else
        config = kube_config
        @kube_auth_options = config.context.auth_options
      end
    end

    def kube_config
      @kube_config ||= Kubeclient::Config.read(kubeconfig_path)
    end

    def in_cluster?
      File.exist?(service_account_token_path)
    end

    def ready_timeout
      kube_setting(:ready_timeout).to_i
    end

    def ready_interval
      kube_setting(:ready_interval).to_f
    end

    def ensure_runtime_namespace_resources(handle, namespace_context)
      return unless isolated_runtime_namespace?(handle.namespace)

      ensure_namespace(handle.namespace, namespace_context)
      ensure_runtime_image_pull_secrets(handle.namespace)
      ensure_terminal_auth_middleware(handle.namespace)
      ensure_runtime_network_policies(handle.namespace)
    end

    def ensure_runtime_image_pull_secrets(namespace)
      agents_image_pull_secrets.each do |secret_name|
        ensure_image_pull_secret(namespace, secret_name)
      end
    end

    def ensure_image_pull_secret(namespace, secret_name)
      core_client.get_secret(secret_name, namespace)
      nil
    rescue StandardError
      source_secret = core_client.get_secret(secret_name, runtime_namespace)
      payload = {
        apiVersion: "v1",
        kind: "Secret",
        metadata: {
          name: secret_name,
          namespace: namespace
        },
        type: source_secret.type,
        data: source_secret.data
      }

      core_client.create_secret(Kubeclient::Resource.new(payload))
    end

    def ensure_namespace(namespace, context)
      core_client.get_namespace(namespace)
    rescue StandardError
      core_client.create_namespace(build_namespace_resource(namespace, context))
    end

    def build_namespace_resource(namespace, context)
      Kubeclient::Resource.new(
        apiVersion: "v1",
        kind: "Namespace",
        metadata: {
          name: namespace,
          labels: namespace_labels(namespace, context)
        }
      )
    end

    def namespace_labels(namespace, context)
      context = (context || {}).with_indifferent_access

      labels = resource_labels(namespace: namespace)

      if context[:project_id].present?
        labels["aixle.com/scope"] = "project"
        labels["aixle.com/project-id"] = context[:project_id].to_s
      elsif context[:user_id].present?
        labels["aixle.com/scope"] = "user"
        labels["aixle.com/user-id"] = context[:user_id].to_s
      else
        labels["aixle.com/scope"] = "shared"
      end

      labels
    end

    # Creates the namespace's terminal-auth middleware, and repairs one created
    # by an older build: those forwarded the browser's Cookie header to the pod.
    def ensure_terminal_auth_middleware(namespace = traefik_namespace)
      existing = begin
        traefik_client.get_entity("middlewares", traefik_auth_middleware, namespace)
      rescue StandardError
        nil
      end
      return traefik_client.create_entity("Middleware", "middlewares", build_terminal_auth_middleware(namespace)) if existing.nil?

      forward_auth = existing.spec&.forwardAuth
      return existing if forward_auth&.authResponseHeadersRegex == TERMINAL_AUTH_RESPONSE_HEADERS_REGEX &&
                         Array(forward_auth&.addAuthCookiesToResponse) == TERMINAL_AUTH_RESPONSE_COOKIES

      repair_terminal_auth_middleware(namespace)
    end

    # The deployed runtime role may create and delete middlewares but not patch
    # them (aixle-infra kube/helmfile/values/aixle-app/common.yaml), so a refused
    # patch falls back to replacing the object. Routes that name it recover as
    # soon as the new one exists.
    def repair_terminal_auth_middleware(namespace)
      traefik_client.patch_entity(
        "middlewares", traefik_auth_middleware,
        { spec: { forwardAuth: { authResponseHeadersRegex: TERMINAL_AUTH_RESPONSE_HEADERS_REGEX,
                                  addAuthCookiesToResponse: TERMINAL_AUTH_RESPONSE_COOKIES } } },
        "merge-patch", namespace
      )
    rescue Kubeclient::HttpError => e
      raise unless [ 403, 405 ].include?(e.error_code.to_i)

      Rails.logger.warn("[KubernetesRuntime] Replacing #{traefik_auth_middleware} in #{namespace}: patch refused (#{e.error_code})")
      traefik_client.delete_entity("middlewares", traefik_auth_middleware, namespace)
      traefik_client.create_entity("Middleware", "middlewares", build_terminal_auth_middleware(namespace))
    end

    def ensure_runtime_network_policies(namespace)
      runtime_network_policies(namespace).each do |policy|
        ensure_network_policy(namespace, policy)
      end
    end

    def ensure_network_policy(namespace, policy)
      networking_client.get_entity("networkpolicies", policy.metadata[:name], namespace)
    rescue StandardError
      networking_client.create_entity("NetworkPolicy", "networkpolicies", policy)
    end

    def runtime_network_policies(namespace)
      [
        build_default_deny_network_policy(namespace),
        build_traefik_ingress_network_policy(namespace),
        build_traefik_ingress_network_policy(namespace, name: "runtime-allow-traefik-view-ingress", ports: [ VIEW_PORT ]),
        build_dns_egress_network_policy(namespace),
        build_aixle_service_egress_network_policy(namespace),
        build_public_internet_egress_network_policy(namespace)
      ]
    end

    def build_default_deny_network_policy(namespace)
      Kubeclient::Resource.new(
        apiVersion: "networking.k8s.io/v1",
        kind: "NetworkPolicy",
        metadata: {
          name: "runtime-default-deny",
          namespace: namespace
        },
        spec: {
          podSelector: {},
          policyTypes: [ "Ingress", "Egress" ]
        }
      )
    end

    # The read-only terminal's port gets a policy of its own rather than an entry
    # in the first: policies only ever add up, and the runtime may create them but
    # not update one that already exists in a project's namespace.
    def build_traefik_ingress_network_policy(namespace, name: "runtime-allow-traefik-ingress", ports: DEFAULT_TRAEFIK_PORTS)
      Kubeclient::Resource.new(
        apiVersion: "networking.k8s.io/v1",
        kind: "NetworkPolicy",
        metadata: {
          name: name,
          namespace: namespace
        },
        spec: {
          podSelector: {},
          policyTypes: [ "Ingress" ],
          ingress: [
            {
              from: [
                {
                  namespaceSelector: {
                    matchLabels: {
                      "kubernetes.io/metadata.name" => runtime_namespace
                    }
                  },
                  podSelector: {
                    matchLabels: {
                      "app" => "traefik"
                    }
                  }
                },
                {
                  namespaceSelector: {
                    matchLabels: {
                      "kubernetes.io/metadata.name" => runtime_namespace
                    }
                  },
                  podSelector: {
                    matchLabels: {
                      "app.kubernetes.io/name" => "traefik"
                    }
                  }
                }
              ],
              ports: ports.map do |port|
                { protocol: "TCP", port: port }
              end
            }
          ]
        }
      )
    end

    def build_dns_egress_network_policy(namespace)
      Kubeclient::Resource.new(
        apiVersion: "networking.k8s.io/v1",
        kind: "NetworkPolicy",
        metadata: {
          name: "runtime-allow-dns-egress",
          namespace: namespace
        },
        spec: {
          podSelector: {},
          policyTypes: [ "Egress" ],
          egress: [
            {
              to: [
                {
                  namespaceSelector: {
                    matchLabels: {
                      "kubernetes.io/metadata.name" => "kube-system"
                    }
                  }
                }
              ],
              ports: [
                { protocol: "UDP", port: 53 },
                { protocol: "TCP", port: 53 }
              ]
            }
          ]
        }
      )
    end

    def build_aixle_service_egress_network_policy(namespace)
      services = [
        [ "web", 4000 ],
        [ "mcp", 4002 ],
        [ "otlp-ingest", 4318 ]
      ]

      Kubeclient::Resource.new(
        apiVersion: "networking.k8s.io/v1",
        kind: "NetworkPolicy",
        metadata: {
          name: "runtime-allow-aixle-service-egress",
          namespace: namespace
        },
        spec: {
          podSelector: {},
          policyTypes: [ "Egress" ],
          egress: services.map do |app, port|
            {
              to: [
                {
                  namespaceSelector: {
                    matchLabels: {
                      "kubernetes.io/metadata.name" => runtime_namespace
                    }
                  },
                  podSelector: {
                    matchLabels: {
                      "app" => app
                    }
                  }
                }
              ],
              ports: [
                { protocol: "TCP", port: port }
              ]
            }
          end
        }
      )
    end

    def build_public_internet_egress_network_policy(namespace)
      egress = [
        {
          to: [
            {
              ipBlock: build_ip_block("0.0.0.0/0", runtime_blocked_ipv4_cidrs)
            }
          ]
        }
      ]

      blocked_ipv6 = runtime_blocked_ipv6_cidrs
      if blocked_ipv6.any?
        egress << {
          to: [
            {
              ipBlock: build_ip_block("::/0", blocked_ipv6)
            }
          ]
        }
      end

      Kubeclient::Resource.new(
        apiVersion: "networking.k8s.io/v1",
        kind: "NetworkPolicy",
        metadata: {
          name: "runtime-allow-public-internet-egress",
          namespace: namespace
        },
        spec: {
          podSelector: {},
          policyTypes: [ "Egress" ],
          egress: egress
        }
      )
    end

    def build_ip_block(cidr, except_cidrs)
      block = { cidr: cidr }
      except_values = Array(except_cidrs).map(&:to_s).map(&:strip).reject(&:blank?).uniq
      block[:except] = except_values if except_values.any?
      block
    end

    def runtime_blocked_ipv4_cidrs
      blocked = kube_cidr_list_setting(:runtime_blocked_ipv4_cidrs)
      vpc_cidr = kube_setting(:eks_vpc_cidr).to_s.strip

      (blocked + [ vpc_cidr ]).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    end

    def runtime_blocked_ipv6_cidrs
      kube_cidr_list_setting(:runtime_blocked_ipv6_cidrs)
    end

    def verify_resources(handle, ports)
      ensure_service(handle, ports)
      ensure_middlewares(handle)
      ensure_ingressroute(handle)
    end

    def ensure_service(handle, ports)
      return if ports.blank? && handle.service_ports.blank?

      # The Service is created asynchronously; on the container-startup path the
      # lookup can hit a transient 404 before it becomes visible
      # (Sentry PALAD-AI-TEMPORAL-G). Retry within the ready window instead of
      # failing the activity on the first miss.
      deadline = Time.current + ready_timeout
      begin
        core_client.get_service(handle.service_name, handle.namespace)
      rescue Kubeclient::ResourceNotFoundError
        if Time.current < deadline
          sleep ready_interval
          retry
        end
        raise
      end
    rescue StandardError => e
      raise "Service not ready: #{handle.service_name} (#{e.message})"
    end

    def ensure_middlewares(handle)
      return if handle.route_token.blank?

      (handle.middleware_names + [ traefik_auth_middleware ]).uniq.each do |name|
        traefik_client.get_entity("middlewares", name, handle.namespace)
      end
    rescue StandardError => e
      raise "Middleware not ready: #{e.message}"
    end

    def ensure_ingressroute(handle)
      return if handle.route_token.blank?

      traefik_client.get_entity("ingressroutes", handle.ingress_name, handle.namespace)
    rescue StandardError => e
      raise "IngressRoute not ready: #{handle.ingress_name} (#{e.message})"
    end

    def wait_for_ports(handle, ports)
      start_time = Time.current
      timeout = ready_timeout

      loop do
        return true if ports.all? { |port| port_open?(handle, port) }

        elapsed = Time.current - start_time
        if elapsed > timeout
          Rails.logger.warn("[KubernetesRuntime] Ports #{ports.inspect} not open after #{elapsed.round(1)}s, proceeding")
          return true
        end

        sleep ready_interval
      end
    end

    def wait_for_traefik_route(handle)
      traefik_url = "#{traefik_probe_base_url}/t/#{handle.route_token}/tty/"
      uri = URI(traefik_url)
      expected_host = route_domain_host
      start_time = Time.current
      timeout = ready_timeout

      loop do
        return true if traefik_route_ready?(uri, expected_host, handle)

        elapsed = Time.current - start_time
        if elapsed > timeout
          Rails.logger.warn("[KubernetesRuntime] Traefik route timeout after #{elapsed.round(1)}s for #{handle.route_token}")
          return true
        end
        sleep ready_interval
      end
    end

    def traefik_route_ready?(uri, expected_host, handle)
      request = Net::HTTP::Head.new(uri.request_uri)
      request["Host"] = expected_host if expected_host.present?

      verify_mode = kube_setting(:traefik_verify_tls) ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        verify_mode: verify_mode,
        open_timeout: 2, read_timeout: 2
      ) { |http| http.request(request) }

      code = response.code.to_i
      # 200/401/403 = route exists and backend is up (auth middleware responded)
      # 404 = route not registered yet; 502/503 = backend not ready yet
      if [ 200, 401, 403 ].include?(code)
        Rails.logger.info("[KubernetesRuntime] Traefik route ready for #{handle.route_token} (#{code})")
        return true
      end

      Rails.logger.debug("[KubernetesRuntime] Traefik route not ready for #{handle.route_token}: #{code}")
      false
    rescue StandardError => e
      Rails.logger.debug("[KubernetesRuntime] Traefik route not ready: #{e.class} #{e.message}")
      false
    end

    def traefik_probe_base_url
      Settings.traefik.http_base.to_s.strip.presence || "https://#{traefik_service_host}"
    end

    def traefik_service_host
      "traefik.#{runtime_namespace}.svc.cluster.local"
    end

    def internal_service_url(service_name, port)
      "http://#{service_name}.#{runtime_namespace}.svc.cluster.local:#{port}"
    end

    def kube_cidr_list_setting(key)
      value = kube_setting(key)
      values = case value
      when String
        value.split(",")
      when Array
        value
      else
        Array(value)
      end

      values.map(&:to_s).map(&:strip).reject(&:blank?).uniq
    end

    def kube_setting(key)
      Settings.kubernetes.public_send(key)
    end
  end
end
