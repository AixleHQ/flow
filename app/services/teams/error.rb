# frozen_string_literal: true

module Teams
  # Teams or Entra refused, or answered with something we cannot use. `status`
  # is the HTTP status when there was one, so callers can tell a throttle from a
  # refusal.
  class Error < StandardError
    attr_reader :status, :retry_after

    def initialize(message = nil, status: nil, retry_after: nil)
      super(message)
      @status = status
      @retry_after = retry_after
    end

    def retryable?
      status.to_i == 429 || status.to_i >= 500
    end
  end
end
