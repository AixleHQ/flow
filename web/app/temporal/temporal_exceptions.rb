# frozen_string_literal: true

require "temporalio/error"

module TemporalExceptions
  # Base class for custom Temporal errors
  class BaseError < Temporalio::Error::ApplicationError
    def initialize(message, **options)
      super(message, **options)
    end
  end

  # Retryable error - will be retried according to retry policy
  #
  # Use for transient errors:
  # - Network timeouts
  # - Rate limits
  # - Temporary service unavailability
  #
  # Example:
  #   raise Temporal::Exceptions::RetryableError.new("Rate limit exceeded")
  class RetryableError < BaseError
    def initialize(message, type: nil)
      super(
        message,
        type: type || "RetryableError",
        non_retryable: false,  # Will retry
      )
    end
  end

  # Non-retryable error - activity will fail immediately without retries
  #
  # Use for permanent errors:
  # - Invalid input data
  # - Missing required resources
  # - Business logic violations
  #
  # Example:
  #   raise Temporal::Exceptions::NonRetryableError.new("Invalid workspace ID")
  class NonRetryableError < BaseError
    def initialize(message, type: nil)
      super(
        message,
        type: type || "NonRetryableError",
        non_retryable: true,  # Won't retry
      )
    end
  end

  # Wrap any Ruby error into Temporal ApplicationError
  #
  # Args:
  #   error: Original exception (ArgumentError, ActiveRecord::RecordNotFound, etc)
  #   retryable: Whether error should be retried (default: true)
  #
  # Returns:
  #   Temporalio::Error::ApplicationError with appropriate settings
  #
  # Example:
  #   begin
  #     user = User.find(id)
  #   rescue ActiveRecord::RecordNotFound => e
  #     raise Temporal::Exceptions.wrap(e, retryable: false)
  #   end
  def self.wrap(error, retryable: true, type: nil, details: nil)
    error_class = retryable ? RetryableError : NonRetryableError

    error_class.new(
      error.message,
      type: error.class.name,
    )
  end
end
