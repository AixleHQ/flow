# frozen_string_literal: true

module AzureDevops
  # A concurrent change: a work item revision moved, or a relation already
  # exists. The recovery is a re-read, never a blind retry.
  class Conflict < Error
    def initialize(message = nil, details: nil)
      super(message, code: "conflict", status: 409, details: details)
    end
  end
end
