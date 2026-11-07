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

  # The runtime of one session (docs/design/agent-runtimes/DESIGN.md §5.3): its
  # runner's for a session on an external runner, and for every other session
  # exactly what `build` gives, so the hosted path is unchanged (§12.3).
  # `op_timeout` caps a runner op's deadline (RunnerRuntime).
  def self.for_session(session, op_timeout: nil)
    session.try(:runner_id) ? RunnerRuntime.new(session, op_timeout: op_timeout) : ContainerRuntime.build
  end

  def self.from_settings
    return "docker" unless defined?(Settings) && Settings.respond_to?(:container_runtime)

    Settings.container_runtime.to_s
  end
end
