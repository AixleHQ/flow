# frozen_string_literal: true

require "docker"
require "json"
require "net/http"
require "uri"

module ContainerRuntime
  # Implements BaseRuntime using the docker-api gem.
  class DockerRuntime < BaseRuntime
    HEALTH_CHECK_TIMEOUT = 30
    HEALTH_CHECK_INTERVAL = 1
    PORT_READY_TIMEOUT = 30
    TRAEFIK_ROUTE_TIMEOUT = 30
    TRAEFIK_ROUTE_INTERVAL = 1

    # -- Lifecycle ------------------------------------------------------------

    def pull_image(image)
      raise ArgumentError, "image is required" if image.blank?

      Rails.logger.info("[DockerRuntime] Checking image: #{image}")

      if image_exists?(image)
        Rails.logger.info("[DockerRuntime] Image cached: #{image}")
        return { status: :cached, image: image, duration_seconds: 0 }
      end

      Rails.logger.info("[DockerRuntime] Pulling image: #{image}")
      start_time = Time.current

      pull_from_registry(image)

      duration = (Time.current - start_time).to_i
      Rails.logger.info("[DockerRuntime] Image pulled: #{image} (#{duration}s)")

      { status: :pulled, image: image, duration_seconds: duration }
    end

    def create_container(spec)
      config = {
        "Image" => spec[:image],
        "Env" => spec[:env_vars] || [],
        "Labels" => spec[:labels] || {},
        "HostConfig" => spec[:host_config] || {}
      }

      config["Cmd"] = spec[:cmd] if spec[:cmd]
      config["WorkingDir"] = spec[:working_dir] if spec[:working_dir]
      config["ExposedPorts"] = spec[:exposed_ports] if spec[:exposed_ports]
      config["name"] = spec[:container_name] if spec[:container_name]

      Docker::Container.create(config)
    end

    def start_container(id)
      container = resolve_container(id)
      container.start
      container
    end

    # -- Execution ------------------------------------------------------------

    # `timeout:` is the runtime-agnostic option (KubernetesRuntime reads it
    # directly). docker-api spells it `wait:`, which it forwards to Excon as the
    # read timeout; without it long execs die on Excon's 60s default with
    # "read timeout reached".
    def exec(id, cmd, opts = {})
      container = resolve_container(id)
      opts = opts.dup
      timeout = opts.delete(:timeout)
      opts[:wait] = timeout if timeout.present?
      container.exec(cmd, opts)
    end

    # -- File I/O -------------------------------------------------------------

    def write_file(id, path, content, mode: 0o644, uid: 0, gid: 0)
      container = resolve_container(id)
      tar_io = build_tar_stream(path, content, mode: mode, uid: uid, gid: gid)
      container.archive_in_stream("/", overwrite: true) { tar_io.read(Excon.defaults[:chunk_size]).to_s }
      true
    rescue StandardError => e
      Rails.logger.warn("[DockerRuntime] write_file failed for #{path}: #{e.message}")
      false
    ensure
      tar_io&.close
    end

    def read_file(id, path)
      container = resolve_container(id)
      tar_content = +""
      container.archive_out(path) { |chunk| tar_content << chunk }
      extract_from_tar(tar_content, File.basename(path))
    rescue Docker::Error::NotFoundError, Docker::Error::ServerError => e
      Rails.logger.debug("[DockerRuntime] read_file not found: #{path} — #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.warn("[DockerRuntime] read_file failed for #{path}: #{e.message}")
      nil
    end

    # -- Introspection --------------------------------------------------------

    def wait_container(id, timeout = nil)
      container = resolve_container(id)
      wait_seconds = timeout || 1800
      container.wait(wait_seconds)
    end

    def container_logs(id, stdout: true, stderr: true)
      container = resolve_container(id)

      stdout_raw = stdout ? container.logs(stdout: true, stderr: false).to_s : ""
      stderr_raw = stderr ? container.logs(stdout: false, stderr: true).to_s : ""

      {
        stdout: demux_docker_logs(stdout_raw),
        stderr: demux_docker_logs(stderr_raw)
      }
    end

    def stop_container(id, timeout = nil, _options = {})
      container = resolve_container(id)
      options = timeout ? { "t" => timeout } : {}
      container.stop(options)
    end

    def remove_container(id, options = {})
      container = resolve_container(id)
      remove_options = options[:force] ? { force: true } : {}
      container.remove(remove_options)
    end

    def remove_image(image)
      return if image.blank?

      begin
        docker_image = Docker::Image.get(image)
        docker_image.remove(force: true)
        Rails.logger.info("[DockerRuntime] Removed image: #{image}")
      rescue Docker::Error::NotFoundError
        # Already gone
      rescue Docker::Error::ConflictError => e
        Rails.logger.warn("[DockerRuntime] Cannot remove image #{image}: #{e.message}")
      rescue StandardError => e
        Rails.logger.warn("[DockerRuntime] Remove image failed: #{e.message}")
      end
    end

    def image_digest(image)
      return nil if image.blank?

      Array(Docker::Image.get(image).info["RepoDigests"]).first
    end

    def wait_for_ready(id, ports = [])
      container = resolve_container(id)
      wait_for_container_health(container)
      wait_for_ports(container, ports)
      wait_for_traffic_route(container)
      true
    end

    def resolve_container(container_id)
      return container_id if container_id.is_a?(Docker::Container)

      Docker::Container.get(container_id)
    rescue Docker::Error::NotFoundError, Docker::Error::ClientError
      nil
    end

    def container_identifier(container)
      return nil if container.blank?
      return container if container.is_a?(String)

      if container.respond_to?(:id)
        id = container.id
        return id[0..11] if id.is_a?(String) && id.present?
      end

      container.to_s
    end

    private

    def wait_for_traffic_route(container)
      route_token = route_token_from_container(container)
      return true if route_token.blank?

      traffic_url = URI("#{Settings.traefik.internal_url}/t/#{route_token}/tty/")
      deadline = Time.current + TRAEFIK_ROUTE_TIMEOUT

      loop do
        begin
          http = Net::HTTP.new(traffic_url.host, traffic_url.port)
          http.open_timeout = 2
          http.read_timeout = 2
          response = http.get(traffic_url.request_uri)
          unless response.is_a?(Net::HTTPNotFound)
            Rails.logger.info("[DockerRuntime] Traffic route ready for #{route_token}")
            return true
          end
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
          Rails.logger.debug("[DockerRuntime] Traffic route not yet ready: #{e.class}")
        end

        if Time.current > deadline
          Rails.logger.warn("[DockerRuntime] Traffic route timeout for #{route_token}, proceeding anyway")
          return true
        end

        sleep TRAEFIK_ROUTE_INTERVAL
      end
    end

    def route_token_from_container(container)
      container_name = container.json["Name"].to_s.delete_prefix("/")
      return nil unless container_name.start_with?("terminal-")

      container_name.delete_prefix("terminal-")
    rescue StandardError => e
      Rails.logger.debug("[DockerRuntime] Failed to resolve route token: #{e.message}")
      nil
    end

    def wait_for_container_health(container, timeout: HEALTH_CHECK_TIMEOUT)
      start_time = Time.current

      loop do
        container.refresh!
        state = container.json["State"]

        if state["Running"]
          Rails.logger.info("[DockerRuntime] Container is running")
          return true
        end

        if state["Status"] == "exited" || state["Status"] == "dead"
          exit_code = state["ExitCode"]
          raise "Container exited with code #{exit_code}"
        end

        elapsed = Time.current - start_time
        raise "Container failed to start within #{timeout}s" if elapsed > timeout

        sleep HEALTH_CHECK_INTERVAL
      end
    end

    def wait_for_ports(container, ports, timeout: PORT_READY_TIMEOUT)
      return if ports.blank?

      start_time = Time.current

      loop do
        all_ready = ports.all? { |port| port_open?(container, port) }
        return true if all_ready

        elapsed = Time.current - start_time
        if elapsed > timeout
          pending = ports.reject { |port| port_open?(container, port) }
          raise "Ports not ready within #{timeout}s: #{pending.join(', ')}"
        end

        sleep 0.5
      end
    end

    def port_open?(container, port)
      hex_port = port.to_s(16).upcase.rjust(4, "0")
      result = container.exec([ "sh", "-c", "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -q ':#{hex_port} ' && echo 'open'" ])
      result[0].join.include?("open")
    rescue StandardError => e
      Rails.logger.debug("[DockerRuntime] Port check error: #{e.message}")
      false
    end

    # Demultiplex Docker log stream (8-byte header per frame)
    # Header: [stream_type(1) | padding(3) | size(4 big-endian)]
    def demux_docker_logs(raw)
      return "" if raw.nil? || raw.empty?

      output = +""
      io = StringIO.new(raw)

      while io.pos < raw.bytesize
        header = io.read(8)
        break unless header && header.bytesize == 8

        size = header[4..7].unpack1("N")
        break unless size&.positive?

        frame = io.read(size)
        break unless frame

        output << frame
      end

      output
    end

    def image_exists?(image)
      Docker::Image.get(image)
      true
    rescue Docker::Error::NotFoundError
      false
    end

    def pull_from_registry(image)
      image_name, tag = parse_image_reference(image)

      Docker::Image.create(
        "fromImage" => image_name,
        "tag" => tag
      ) do |chunk|
        log_pull_progress(chunk)
      end
    end

    def parse_image_reference(image)
      if image.include?(":")
        parts = image.rpartition(":")
        [ parts[0], parts[2] ]
      else
        [ image, "latest" ]
      end
    end

    def log_pull_progress(chunk)
      return unless chunk.is_a?(String)

      data = JSON.parse(chunk) rescue nil
      return unless data

      if data["status"] && data["progress"]
        Rails.logger.debug("[DockerRuntime] #{data['status']}: #{data['progress']}")
      end
    end
  end
end
