# frozen_string_literal: true

module PullRequests
  # What a pull-request call failed with, shaped for a tool to hand to an agent:
  # a stable `code`, a readable message, optional details. Adapters translate
  # their provider's errors into these with `.from`, keeping the provider's code.
  class Error < StandardError
    attr_reader :code, :details

    def initialize(message = nil, code: "pull_request_error", details: nil)
      super(message || code.to_s)
      @code = code.to_s
      @details = details
    end

    def to_h
      { error: code, message: message, details: details }.compact
    end

    def self.from(error)
      return error if error.is_a?(Error)

      new(error.message, code: error.respond_to?(:code) ? error.code : "provider_error",
                         details: (error.details if error.respond_to?(:details)))
    end

    # The pull request moved on or is in a state the request did not expect;
    # `details` says what it is now.
    class Conflict < Error
      def initialize(message = nil, details: nil) = super(message, code: "conflict", details: details)
    end

    # The request left Aixle and no answer came back. Not a failure: reissuing it
    # blindly is how duplicate pull requests and comments get made.
    class OutcomeUnknown < Error
      def initialize(message = nil) = super(message, code: "outcome_unknown")
    end

    # This host cannot do what was asked.
    class Unsupported < Error
      def initialize(message = nil) = super(message, code: "unsupported")
    end
  end
end
