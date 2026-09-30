# frozen_string_literal: true

module Jira
  # Callers — the tracker provider, the connect flow — branch on `code`, never on
  # Atlassian's wording.
  class Error < StandardError
    attr_reader :code, :status, :details

    def initialize(message = nil, code: "jira_error", status: nil, details: nil)
      super(message || code.to_s)
      @code = code.to_s
      @status = status
      @details = details
    end

    def to_h
      { error: code, message: message, details: details }.compact
    end

    # The request left and no answer came back, so a write may have landed.
    class OutcomeUnknown < Error
      def initialize(message = nil) = super(message, code: "outcome_unknown")
    end
  end
end
