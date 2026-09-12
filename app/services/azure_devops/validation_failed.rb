# frozen_string_literal: true

module AzureDevops
  # Azure rejected the request shape, a field value, or a process rule.
  class ValidationFailed < Error
    def initialize(message = nil, details: nil)
      super(message, code: "validation_failed", status: 400, details: details)
    end
  end
end
