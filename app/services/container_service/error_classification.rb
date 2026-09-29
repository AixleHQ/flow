# frozen_string_literal: true

class ContainerService
  # What a phase failure means, read from the error the runtime raised (not the
  # PhaseError around it) — the decision table in
  # docs/architecture/temporal-error-handling.md, as code:
  #
  #   :transient — the network or the runtime had a moment (timeouts, refused or
  #                reset connections, a 5xx or 429 from the Docker or Kubernetes
  #                API): retry the phase.
  #   :gone      — the object is not there: expected while cleaning up, a real
  #                problem anywhere else.
  #   :fatal     — anything else: do not retry, report it.
  module ErrorClassification
    NETWORK = [
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
      Errno::EPIPE, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError, EOFError
    ].freeze

    module_function

    def classify(error)
      return :gone if gone?(error)
      return :transient if transient?(error)

      :fatal
    end

    def gone?(error)
      error.is_a?(Kubeclient::ResourceNotFoundError) || docker_error?(error, "NotFoundError")
    end

    def transient?(error)
      return true if NETWORK.any? { |klass| error.is_a?(klass) }
      return true if defined?(Excon::Error::Socket) && (error.is_a?(Excon::Error::Socket) || error.is_a?(Excon::Error::Timeout))
      return true if docker_error?(error, "ServerError") || docker_error?(error, "TimeoutError")
      return false unless error.is_a?(Kubeclient::HttpError)

      code = error.error_code.to_i
      code.zero? || code == 429 || code >= 500
    end

    def docker_error?(error, name)
      defined?(Docker::Error) && Docker::Error.const_defined?(name) && error.is_a?(Docker::Error.const_get(name))
    end
  end
end
