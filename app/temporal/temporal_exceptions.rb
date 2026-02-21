# frozen_string_literal: true

require "temporalio/error"

module TemporalExceptions
  BENIGN = Temporalio::Error::ApplicationError::Category::BENIGN
  UNSPECIFIED = Temporalio::Error::ApplicationError::Category::UNSPECIFIED

  # Wrap any Ruby error into Temporal ApplicationError.
  #
  # Called inside a rescue block — Ruby automatically preserves the cause chain.
  #
  # @param error [StandardError] original exception
  # @param retryable [Boolean] whether Temporal should retry (default: true)
  # @param benign [Boolean] expected error — suppresses metrics and downgrades logs to DEBUG
  # @param type [String, nil] error type for workflow-side matching (defaults to error class name)
  def self.wrap(error, retryable: true, benign: false, type: nil)
    Temporalio::Error::ApplicationError.new(
      error.message,
      type: type || error.class.name,
      non_retryable: !retryable,
      category: benign ? BENIGN : UNSPECIFIED
    )
  end

  # Convenience for non-retryable wrap.
  def self.non_retryable(error, benign: false, type: nil)
    wrap(error, retryable: false, benign: benign, type: type)
  end
end
