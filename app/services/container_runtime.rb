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
end
