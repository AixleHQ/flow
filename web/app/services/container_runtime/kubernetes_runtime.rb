# frozen_string_literal: true

require "kubeclient"
require "ostruct"
require "securerandom"
require "shellwords"
require "tempfile"
require "uri"
require "websocket-client-simple"

module ContainerRuntime
  # KubernetesRuntime
  # Implements BaseRuntime using Kubernetes Pods + Services + IngressRoutes.
  class KubernetesRuntime < BaseRuntime
    DEFAULT_SERVICE_PORTS = [ 7681, 4040 ].freeze
    DEFAULT_CONTAINER_NAME = "main"
    DEFAULT_WORKSPACE_DIR = "/workspace"
    READY_TIMEOUT = 30
    READY_INTERVAL = 1

    def pull_image(image)
      raise ArgumentError, "image is required" if image.blank?

      Rails.logger.info("[KubernetesRuntime] Pull image is a no-op: #{image}")
      { status: :skipped, image: image, duration_seconds: 0 }
    end

    def create_container(spec)
      handle = build_handle(spec)
      pod = build_pod(spec, handle)

      core_client.create_pod(pod)
      Rails.logger.info("[KubernetesRuntime] Pod created: #{handle.pod_name}")

      handle
    end

    def start_container(id)
      handle = resolve_handle(id)

      if handle.service_ports.any?
        create_service(handle)
        create_middlewares(handle)
        create_ingressroute(handle) if handle.route_token.present?
      end

      handle
    end

    def exec(id, cmd, opts = {})
      handle = resolve_handle(id)
      stdout, stderr, exit_code = exec_via_websocket(handle, cmd, opts)

      stdout_lines = stdout.empty? ? [] : stdout.split("\n").map { |line| "#{line}\n" }
      stderr_lines = stderr.empty? ? [] : stderr.split("\n").map { |line| "#{line}\n" }

      [ stdout_lines, stderr_lines, exit_code ]
    end

    def copy_from(id, path)
      return "" if path.blank?

      handle = resolve_handle(id)
      normalized = normalize_tar_path(path)
      return "" if normalized.blank?

      output = Tempfile.new("palad-copy-from")
      output.binmode
      cmd = [ "/bin/sh", "-c", "tar -cf - -C / #{Shellwords.escape(normalized)}" ]
      _stdout, _stderr, exit_code = exec_via_websocket(handle, cmd, stdout_io: output, binary: true)

      return "" unless exit_code.to_i.zero?

      output.rewind
      output.read
    ensure
      output&.close!
    end

    def copy_to(id, path, content)
      return false if path.blank?

      handle = resolve_handle(id)
      tar_io = build_tar_stream(path, content.to_s)
      cmd = [ "/bin/sh", "-c", "tar -xf - -C /" ]
      _stdout, _stderr, exit_code = exec_via_websocket(
        handle,
        cmd,
        stdin_io: tar_io,
        binary: true,
        close_on_stdin_eof: true
      )

      exit_code.to_i.zero?
    ensure
      tar_io&.close!
    end

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
      # Images are managed by the Kubernetes node runtime.
      # No-op by default.
    end

    def wait_for_ready(id, ports = [])
      handle = resolve_handle(id)
      wait_for_pod_ready(handle)

      verify_resources(handle, ports)

      return true if ports.blank?

      ports.all? { |port| port_open?(handle, port) }
    end

    def resolve_container(container_id)
      resolve_handle(container_id)
    end

    def container_identifier(container)
      return nil if container.blank?
      return container if container.is_a?(String)

      return container.pod_name if container.respond_to?(:pod_name)

      if container.respond_to?(:id)
        id = container.id
        return id[0..11] if id.is_a?(String) && id.present?
      end

      container.to_s
    end

    private

    def resolve_handle(id)
      return id if id.is_a?(OpenStruct)
      return id if id.respond_to?(:pod_name)

      OpenStruct.new(
        pod_name: id.to_s,
        namespace: runtime_namespace,
        container_name: DEFAULT_CONTAINER_NAME,
        service_name: id.to_s,
        ingress_name: "#{id}-ingress",
        middleware_names: [],
        route_token: nil,
        service_ports: []
      )
    end

    def build_handle(spec)
      container_name = spec[:container_name]
      route_token = extract_route_token(container_name)
      pod_name = sanitize_name(container_name || "palad-#{SecureRandom.hex(6)}")
      service_ports = extract_ports(spec[:exposed_ports])

      OpenStruct.new(
        pod_name: pod_name,
        namespace: runtime_namespace,
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
      mount_paths = build_mount_paths(spec, env_vars)
      volumes, volume_mounts = build_volumes(mount_paths)

      container = {
        name: handle.container_name,
        image: spec[:image],
        imagePullPolicy: image_pull_policy,
        env: env_vars,
        command: spec[:cmd],
        workingDir: spec[:working_dir],
        volumeMounts: volume_mounts
      }

      ports = handle.service_ports
      container[:ports] = ports.map { |port| { containerPort: port } } if ports.any?

      labels = { "app" => "palad-runtime", "palad-container" => handle.pod_name }

      Kubeclient::Resource.new(
        apiVersion: "v1",
        kind: "Pod",
        metadata: {
          name: handle.pod_name,
          namespace: handle.namespace,
          labels: labels
        },
        spec: {
          restartPolicy: "Never",
          containers: [ container ],
          volumes: volumes
        }
      )
    end

    def create_service(handle)
      labels = { "app" => "palad-runtime", "palad-container" => handle.pod_name }

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
          namespace: handle.namespace
        },
        spec: {
          entryPoints: [ traefik_entrypoint ],
          tls: {},
          routes: [
            build_route(handle, "tty", 7681, [ traefik_auth_middleware, "#{handle.pod_name}-tty-strip" ]),
            build_route(handle, "fs", 4040, [ traefik_cors_middleware, traefik_auth_middleware, "#{handle.pod_name}-fs-strip" ])
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

      ws = WebSocket::Client::Simple.connect(url.to_s, headers: headers)

      ws.on(:open) do
        next unless stdin_io

        Thread.new do
          begin
            stdin_io.rewind if stdin_io.respond_to?(:rewind)
            while (chunk = stdin_io.read(16_384))
              ws.send([ 0 ].pack("C") + chunk)
            end
            ws.close if close_on_stdin_eof
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
          if stderr_io
            stderr_io.write(payload)
          else
            stderr << payload
          end
        end
      end

      ws.on(:error) do |msg|
        mutex.synchronize do
          error = msg
          exit_code = 1
          done = true
          cv.broadcast
        end
      end

      ws.on(:close) do |_msg|
        mutex.synchronize do
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

      ws.close

      raise error if error.is_a?(StandardError)

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

    def build_exec_command(cmd, tty)
      if cmd.is_a?(String)
        [ "/bin/sh", "-c", cmd ]
      elsif cmd.is_a?(Array) && cmd.size == 1
        [ "/bin/sh", "-c", cmd.first.to_s ]
      elsif tty == false
        joined = Array(cmd).map { |word| "\"#{word}\"" }.join(" ")
        [ "/bin/sh", "-c", joined ]
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
      core_client.instance_variable_get(:@headers) || {}
    end

    def build_env_vars(env_vars)
      (env_vars || []).filter_map do |pair|
        next if pair.blank?

        key, value = pair.split("=", 2)
        next if key.blank?

        { name: key, value: value.to_s }
      end
    end

    def build_mount_paths(spec, env_vars)
      paths = []
      tmpfs = spec.dig(:host_config, "Tmpfs") || {}
      paths.concat(tmpfs.keys)

      paths.compact.uniq
    end

    def build_volumes(paths)
      volumes = []
      mounts = []

      paths.each_with_index do |path, index|
        volume_name = "vol-#{index}"
        volumes << {
          name: volume_name,
          emptyDir: empty_dir_for_path(path)
        }
        mounts << {
          name: volume_name,
          mountPath: path
        }
      end

      [ volumes, mounts ]
    end

    def empty_dir_for_path(path)
      tmpfs = path.start_with?("/tmp") || path.include?("/.config")
      tmpfs ? { medium: "Memory" } : {}
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
      sanitized = "palad" if sanitized.empty?
      sanitized[0, 63]
    end

    def build_strip_middleware(handle, suffix, prefix)
      Kubeclient::Resource.new(
        apiVersion: "traefik.io/v1alpha1",
        kind: "Middleware",
        metadata: {
          name: "#{handle.pod_name}-#{suffix}-strip",
          namespace: handle.namespace
        },
        spec: {
          stripPrefix: {
            prefixes: [ prefix ]
          }
        }
      )
    end

    def build_route(handle, suffix, port, middlewares)
      {
        match: "PathPrefix(`/t/#{handle.route_token}/#{suffix}`)",
        kind: "Rule",
        middlewares: middlewares.map { |name| { name: name } },
        services: [
          {
            name: handle.service_name,
            port: port
          }
        ]
      }
    end

    def traefik_entrypoint
      kube_setting(:traefik_entrypoint, "websecure")
    end

    def traefik_auth_middleware
      kube_setting(:traefik_auth_middleware, "terminal-auth")
    end

    def traefik_cors_middleware
      kube_setting(:traefik_cors_middleware, "terminal-cors")
    end

    def runtime_namespace
      kube_setting(:namespace, "palad")
    end

    def workspace_dir
      kube_setting(:workspace_dir, DEFAULT_WORKSPACE_DIR)
    end

    def image_pull_policy
      kube_setting(:image_pull_policy, "IfNotPresent")
    end

    def service_account_token_path
      kube_setting(:service_account_token_path, "/var/run/secrets/kubernetes.io/serviceaccount/token")
    end

    def service_account_ca_path
      kube_setting(:service_account_ca_path, "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
    end

    def kubeconfig_path
      kube_setting(:kubeconfig_path, "/root/.kube/config")
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

    def traefik_api_endpoint
      "#{kube_endpoint}/apis/traefik.io"
    end

    def kube_endpoint
      return @kube_endpoint if defined?(@kube_endpoint)

      if in_cluster?
        host = kube_setting(:service_host, "kubernetes.default.svc")
        port = kube_setting(:service_port, "443")
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
      kube_setting(:ready_timeout, READY_TIMEOUT).to_i
    end

    def ready_interval
      kube_setting(:ready_interval, READY_INTERVAL).to_f
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

      handle.middleware_names.each do |name|
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

    def kube_setting(key, default)
      return default unless defined?(Settings) && Settings.respond_to?(:kubernetes)

      value = Settings.kubernetes&.public_send(key) rescue nil
      value.present? ? value : default
    end
  end
end
