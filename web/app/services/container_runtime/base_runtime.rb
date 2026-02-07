# frozen_string_literal: true

module ContainerRuntime
  def self.build(name = nil)
    runtime_name = name.to_s
    runtime_name = from_settings if runtime_name.strip.empty?

    case runtime_name.to_s
    when "k8s", "kubernetes"
      KubernetesRuntime.new
    else
      DockerRuntime.new
    end
  end

  def self.from_settings
    return "docker" unless defined?(Settings) && Settings.respond_to?(:container_runtime)

    Settings.container_runtime.to_s
  end

  # BaseRuntime
  # Abstract interface for container lifecycle operations.
  class BaseRuntime
    def pull_image(_image)
      raise NotImplementedError, "#{self.class.name} must implement #pull_image"
    end

    def create_container(_spec)
      raise NotImplementedError, "#{self.class.name} must implement #create_container"
    end

    def start_container(_id)
      raise NotImplementedError, "#{self.class.name} must implement #start_container"
    end

    def exec(_id, _cmd, _opts = {})
      raise NotImplementedError, "#{self.class.name} must implement #exec"
    end

    def copy_from(_id, _path)
      raise NotImplementedError, "#{self.class.name} must implement #copy_from"
    end

    def stop_container(_id, _timeout = nil, _options = {})
      raise NotImplementedError, "#{self.class.name} must implement #stop_container"
    end

    def remove_container(_id, _options = {})
      raise NotImplementedError, "#{self.class.name} must implement #remove_container"
    end

    def remove_image(_image)
      # Optional no-op by default.
    end

    def wait_for_ready(_id, _ports = [])
      raise NotImplementedError, "#{self.class.name} must implement #wait_for_ready"
    end
  end
end
