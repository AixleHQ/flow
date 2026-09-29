# frozen_string_literal: true

module ContainerRuntime
  # Raised by #wait_container when the workload can never start because its
  # image cannot be pulled.
  class ImagePullError < StandardError; end
end
