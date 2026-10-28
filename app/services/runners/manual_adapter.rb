# frozen_string_literal: true

module Runners
  # A machine the operator installed `aixle-runner` on. The platform creates,
  # rebuilds and calls nothing (docs/design/agent-runtimes/DESIGN.md §5.1).
  class ManualAdapter < Adapter
    def self.type = "manual"

    def capabilities(_runner)
      Capabilities.new(provisionable: false, rebuildable: false)
    end

    # §2.7 and §6.8: the home directory to mount is the operator's to name, a
    # writable host mount is outside the scrub guarantee (§7.2) so each one is
    # acknowledged, and the Docker socket is root on the machine.
    def validate_config(runner)
      config = runner.config.to_h.deep_stringify_keys
      home_mount_errors(config) + acknowledgement_errors(config) + docker_socket_errors(config)
    end

    private

    def home_mount_errors(config)
      home = ConfigSchema.value(config, "container.home_mount")
      return [] if home.nil? || home["path"].present?

      [ "container.home_mount.path is required on a manual runner" ]
    end

    def acknowledgement_errors(config)
      acknowledged = ConfigSchema.value(config, "container.acknowledged_writable_mounts")
      (writable_host_mounts(config) - acknowledged).map do |target|
        "container.acknowledged_writable_mounts must list #{target}: it is a writable host mount"
      end
    end

    # The home mount has no target of its own, so it is acknowledged by the
    # host path it mounts.
    def writable_host_mounts(config)
      home = ConfigSchema.value(config, "container.home_mount")
      extra = ConfigSchema.value(config, "container.extra_mounts").select { |m| m["writable"] == true }
      cache = ConfigSchema.value(config, "container.cache_mounts").select { |m| m["host_path"].present? }

      [ (home["path"] if home&.dig("writable") == true && home["path"].present?),
        *extra.pluck("target"), *cache.pluck("target") ].compact.uniq
    end

    def docker_socket_errors(config)
      return [] unless ConfigSchema.value(config, "container.docker_socket") == true
      return [] if ConfigSchema.value(config, "container.allow_privileged_mounts") == true

      [ "container.docker_socket requires container.allow_privileged_mounts: it gives the agent root on the machine" ]
    end
  end
end
