# frozen_string_literal: true

module ContainerRuntime
  # KubernetesRuntime
  # Placeholder implementation for Kubernetes pods runtime.
  class KubernetesRuntime < BaseRuntime
    def pull_image(_image)
      raise NotImplementedError, "KubernetesRuntime#pull_image is not implemented"
    end

    def create_container(_spec)
      raise NotImplementedError, "KubernetesRuntime#create_container is not implemented"
    end

    def start_container(_id)
      raise NotImplementedError, "KubernetesRuntime#start_container is not implemented"
    end

    def exec(_id, _cmd, _opts = {})
      raise NotImplementedError, "KubernetesRuntime#exec is not implemented"
    end

    def copy_from(_id, _path)
      raise NotImplementedError, "KubernetesRuntime#copy_from is not implemented"
    end

    def stop_container(_id, _timeout = nil, _options = {})
      raise NotImplementedError, "KubernetesRuntime#stop_container is not implemented"
    end

    def remove_container(_id, _options = {})
      raise NotImplementedError, "KubernetesRuntime#remove_container is not implemented"
    end

    def remove_image(_image)
      # Images are managed by the Kubernetes node runtime.
      # No-op by default.
    end

    def wait_for_ready(_id, _ports = [])
      raise NotImplementedError, "KubernetesRuntime#wait_for_ready is not implemented"
    end
  end
end
