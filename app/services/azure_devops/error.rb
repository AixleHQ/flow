# frozen_string_literal: true

module AzureDevops
  # Base of the adapter's error family. Callers — tool handlers, the git
  # credential endpoint, the connection UI — branch on `code`, never on a
  # provider message, so the codes stay stable while Azure's wording does not.
  # The codes are the ones in §10 of docs/design/azure-devops-integration.md.
  class Error < StandardError
    attr_reader :code, :status, :details

    def initialize(message = nil, code: "azure_error", status: nil, details: nil)
      super(message || code.to_s)
      @code = code.to_s
      @status = status
      @details = details
    end

    def to_h
      { error: code, message: message, details: details }.compact
    end
  end
end
