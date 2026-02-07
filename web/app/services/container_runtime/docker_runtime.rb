# frozen_string_literal: true

require "docker"
require "json"

module ContainerRuntime
  # DockerRuntime
  # Implements BaseRuntime using docker-api.
  class DockerRuntime < BaseRuntime
    HEALTH_CHECK_TIMEOUT = 30
    HEALTH_CHECK_INTERVAL = 1

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

    def exec(id, cmd, opts = {})
      container = resolve_container(id)
      container.exec(cmd, opts)
    end

    def copy_from(id, path)
      container = resolve_container(id)
      container.archive(path)
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

    def wait_for_ready(id, ports = [])
      container = resolve_container(id)
      wait_for_container_health(container)
      wait_for_ports(container, ports)
      true
    end

    private

    def resolve_container(id)
      return id if id.is_a?(Docker::Container)

      Docker::Container.get(id)
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

    def wait_for_ports(container, ports, timeout: 10)
      return if ports.blank?

      start_time = Time.current

      loop do
        all_ready = ports.all? { |port| port_open?(container, port) }
        return true if all_ready

        elapsed = Time.current - start_time
        return false if elapsed > timeout

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
