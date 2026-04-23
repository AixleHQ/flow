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
    DEFAULT_CONTAINER_NAME = "main"
    DEFAULT_WORKSPACE_DIR = "/workspace"
    DEFAULT_TRAEFIK_PORTS = [ 7681, 4040, 8443 ].freeze
    READY_TIMEOUT = 30
    READY_INTERVAL = 1

    # -- Lifecycle ------------------------------------------------------------

    def pull_image(image)
      raise ArgumentError, "image is required" if image.blank?

      Rails.logger.info("[KubernetesRuntime] Pull image is a no-op: #{image}")
      { status: :skipped, image: image, duration_seconds: 0 }
    end

    def create_container(spec)
      handle = build_handle(spec)
      ensure_runtime_namespace_resources(handle, spec[:namespace_context])
      pod = build_pod(spec, handle)

      core_client.create_pod(pod)
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
        close_on_stdin_eof: true
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

    private

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
        middleware_names: [ "#{pod_name}-tty-strip", "#{pod_name}-fs-strip" ],
        route_token: route_token,
        service_ports: service_ports
      )
    end

    def build_pod(spec, handle)
      env_vars = build_env_vars(spec[:env_vars])

      container = {
        name: handle.container_name,
        image: spec[:image],
        imagePullPolicy: image_pull_policy,
        env: env_vars,
        command: spec[:cmd],
        workingDir: spec[:working_dir],
        resources: runtime_container_resources
      }

      ports = handle.service_ports
      container[:ports] = ports.map { |port| { containerPort: port } } if ports.any?

      labels = { "app" => "aixle-runtime", "aixle-container" => handle.pod_name }
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

    def create_service(handle)
      labels = { "app" => "aixle-runtime", "aixle-container" => handle.pod_name }

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
          namespace: handle.namespace
        },
        spec: {
          selector: labels,
          ports: ports
        }
      )

      core_client.create_service(service)
      Rails.logger.info("[KubernetesRuntime] Service created: #{handle.service_name}")
    end

    def create_middlewares(handle)
      return if handle.route_token.blank?

      tty_strip = build_strip_middleware(handle, "tty", "/t/#{handle.route_token}/tty")
      fs_strip = build_strip_middleware(handle, "fs", "/t/#{handle.route_token}/fs")

      traefik_client.create_entity("Middleware", "middlewares", tty_strip)
      traefik_client.create_entity("Middleware", "middlewares", fs_strip)
    end

    def create_ingressroute(handle)
      ingress = Kubeclient::Resource.new(
        apiVersion: "traefik.io/v1alpha1",
        kind: "IngressRoute",
        metadata: {
          name: handle.ingress_name,
          namespace: handle.namespace,
          labels: resource_labels(namespace: handle.namespace)
        },
        spec: {
          entryPoints: [ traefik_entrypoint ],
          tls: {},
          routes: [
            build_route(handle, "tty", 7681, [ traefik_auth_middleware, "#{handle.pod_name}-tty-strip" ]),
            build_route(handle, "fs", 4040, [ traefik_auth_middleware, "#{handle.pod_name}-fs-strip" ]),
            build_route(handle, "ide", 8443, [ traefik_auth_middleware ])
          ]
        }
      )

      traefik_client.create_entity("IngressRoute", "ingressroutes", ingress)
      Rails.logger.info("[KubernetesRuntime] IngressRoute created: #{handle.ingress_name}")
    end

    def delete_ingressroute(handle)
      traefik_client.delete_entity("ingressroutes", handle.ingress_name, handle.namespace)
    end

    def delete_middlewares(handle)
      handle.middleware_names.each do |name|
        traefik_client.delete_entity("middlewares", name, handle.namespace)
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
        raise "Pod failed to start within #{timeout}s" if elapsed > timeout

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
      headers = websocket_headers
      timeout = opts[:timeout].to_i
      timeout = 30 if timeout <= 0

      stdout_io = opts[:stdout_io]
      stderr_io = opts[:stderr_io]
      stdin_io = opts[:stdin_io]
      binary = opts[:binary]
      close_on_stdin_eof = opts[:close_on_stdin_eof]

      stdout = +""
      stderr = +""
      exit_code = 0
      done = false
      error = nil
      mutex = Mutex.new
      cv = ConditionVariable.new
      ws_state = { closed: false }
      runtime = self

      ws = WebSocket::Client::Simple.connect(url.to_s, headers: headers)
      exit_code_parser = method(:exit_code_from_status_payload)

      ws.on(:open) do
        next unless stdin_io

        Thread.new do
          begin
            stdin_io.rewind if stdin_io.respond_to?(:rewind)
            while (chunk = stdin_io.read(16_384))
              break if runtime.send(:websocket_closed?, ws, ws_state)
              ws.send([ 0 ].pack("C") + chunk)
            end
            ws.close if close_on_stdin_eof && !runtime.send(:websocket_closed?, ws, ws_state)
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

      ws.on(:message) do |msg|
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

      ws.on(:error) do |msg|
        next if runtime.send(:websocket_closed?, ws, ws_state)

        Rails.logger.warn("[KubernetesRuntime] WebSocket error: #{msg.inspect}")
        mutex.synchronize do
          error = msg
          exit_code = 1
          done = true
          cv.broadcast
        end
      end

      ws.on(:close) do |_msg|
        mutex.synchronize do
          ws_state[:closed] = true
          done = true
          cv.broadcast
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

      if error.is_a?(StandardError)
        raise error
      elsif error
        Rails.logger.warn("[KubernetesRuntime] Exec error: #{error}")
      end

      [ stdout, stderr, exit_code ]
    rescue StandardError => e
      Rails.logger.warn("[KubernetesRuntime] Exec failed: #{e.message}")
      [ "", "", 1 ]
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

    def websocket_headers
      headers = core_client.instance_variable_get(:@headers) || {}
      # Request v4 exec channel protocol to receive status/exit code frames.
      headers.merge("Sec-WebSocket-Protocol" => "v4.channel.k8s.io")
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
          labels: resource_labels(namespace: handle.namespace)
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
            authResponseHeadersRegex: "^X-"
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

    def route_domain_host
      Settings.domain.to_s.strip.presence
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
      ensure_namespace_resource_quota(handle.namespace, namespace_context)
    end

    def ensure_namespace_resource_quota(namespace, context)
      context = (context || {}).with_indifferent_access

      scope_type, quota_record = if context[:project_id].present?
        [ "Project", NamespaceResourceQuota.find_by(scope_type: "Project", scope_id: context[:project_id]) ]
      elsif context[:user_id].present?
        [ "User", NamespaceResourceQuota.find_by(scope_type: "User", scope_id: context[:user_id]) ]
      else
        [ nil, nil ]
      end

      hard_limits = build_quota_hard_limits(quota_record, scope_type)
      return if hard_limits.empty?

      quota_name = "aixle-resource-quota"

      resource = Kubeclient::Resource.new(
        apiVersion: "v1",
        kind: "ResourceQuota",
        metadata: {
          name: quota_name,
          namespace: namespace
        },
        spec: {
          hard: hard_limits
        }
      )

      begin
        existing = core_client.get_resource_quota(quota_name, namespace)
        if existing.spec.hard != hard_limits
          resource.metadata.resourceVersion = existing.metadata.resourceVersion
          core_client.update_resource_quota(resource)
        end
      rescue Kubeclient::ResourceNotFoundError
        core_client.create_resource_quota(resource)
      end
    end

    def build_quota_hard_limits(quota_record, scope_type)
      settings_key = scope_type == "Project" ? :project_defaults : :user_defaults
      defaults = Settings.namespace_resource_quotas&.send(settings_key) || {}

      fields = %i[cpu_requests memory_requests cpu_limits memory_limits max_pods]

      merged = fields.each_with_object({}) do |field, hash|
        value = quota_record&.send(field)
        value = defaults[field] if value.nil?
        hash[field] = value unless value.nil?
      end

      hard = {}
      hard["requests.cpu"]    = merged[:cpu_requests].to_s    if merged.key?(:cpu_requests)
      hard["requests.memory"] = merged[:memory_requests].to_s if merged.key?(:memory_requests)
      hard["limits.cpu"]      = merged[:cpu_limits].to_s      if merged.key?(:cpu_limits)
      hard["limits.memory"]   = merged[:memory_limits].to_s   if merged.key?(:memory_limits)
      hard["count/pods"]      = merged[:max_pods].to_s        if merged.key?(:max_pods)
      hard
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

    def ensure_terminal_auth_middleware(namespace = traefik_namespace)
      traefik_client.get_entity("middlewares", traefik_auth_middleware, namespace)
    rescue StandardError
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

    def build_traefik_ingress_network_policy(namespace)
      Kubeclient::Resource.new(
        apiVersion: "networking.k8s.io/v1",
        kind: "NetworkPolicy",
        metadata: {
          name: "runtime-allow-traefik-ingress",
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
              ports: DEFAULT_TRAEFIK_PORTS.map do |port|
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

      core_client.get_service(handle.service_name, handle.namespace)
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
        request = Net::HTTP::Head.new(uri.request_uri)
        request["Host"] = expected_host if expected_host.present?

        response = Net::HTTP.start(
          uri.host, uri.port,
          use_ssl: uri.scheme == "https",
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
      rescue StandardError => e
        Rails.logger.debug("[KubernetesRuntime] Traefik route not ready: #{e.class} #{e.message}")
      ensure
        elapsed = Time.current - start_time
        if elapsed > timeout
          Rails.logger.warn("[KubernetesRuntime] Traefik route timeout after #{elapsed.round(1)}s for #{handle.route_token}")
          return true
        end
        sleep ready_interval
      end
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
