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
  # @param details [Array<Object>, Object, nil] secret-safe structured detail(s) to attach —
  #   serialized onto the Temporal ApplicationError so they survive to the workflow/history
  #   instead of being dropped along with everything but `error.message`.
  def self.wrap(error, retryable: true, benign: false, type: nil, details: nil)
    # Array(hash) flattens it to key/value pairs — wrap non-Array details in an
    # Array ourselves instead, so a single details Hash reaches the SDK intact.
    detail_list = details.nil? ? [] : (details.is_a?(Array) ? details : [ details ])

    Temporalio::Error::ApplicationError.new(
      error.message,
      *detail_list,
      type: type || error.class.name,
      non_retryable: !retryable,
      category: benign ? BENIGN : UNSPECIFIED
    )
  end

  # Convenience for non-retryable wrap.
  def self.non_retryable(error, benign: false, type: nil, details: nil)
    wrap(error, retryable: false, benign: benign, type: type, details: details)
  end
end
