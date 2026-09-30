# frozen_string_literal: true

module Trackers
  # What a tracker call failed with, in a shape a tool can hand to an agent
  # as-is: a stable `code`, a readable message, and optional details.
  class Error < StandardError
    attr_reader :code, :details

    def initialize(message = nil, code: "tracker_error", details: nil)
      super(message)
      @code = code
      @details = details
    end

    def to_h
      { error: code, message: message, details: details }.compact
    end

    # Someone else changed the issue first; `details` says what it is now.
    class Conflict < Error
      def initialize(message = nil, details: nil) = super(message, code: "conflict", details: details)
    end

    # The request left Aixle and no answer came back. Not a failure: reissuing it
    # blindly is how duplicate issues and comments get filed.
    class OutcomeUnknown < Error
      def initialize(message = nil) = super(message, code: "outcome_unknown")
    end
  end
end
