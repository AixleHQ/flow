# frozen_string_literal: true

module AzureDevops
  # The request left Aixle and its outcome was never observed. Deliberately NOT a
  # failure: reissuing it is what creates duplicate pull requests and comments,
  # so the recovery path is a read.
  class OutcomeUnknown < Error
    def initialize(message = nil, details: nil)
      super(message, code: "outcome_unknown", status: nil, details: details)
    end
  end
end
