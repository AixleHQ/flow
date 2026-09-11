# frozen_string_literal: true

module AzureDevops
  # Azure publishes a delay rather than a fixed requests-per-minute quota, and
  # can attach one to a SUCCESSFUL response too — so `retry_after` travels with
  # the error rather than being inferred from a constant.
  class RateLimited < Error
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil)
      super(message, code: "rate_limited", status: 429)
      @retry_after = retry_after
    end
  end
end
