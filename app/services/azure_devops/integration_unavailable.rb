# frozen_string_literal: true

module AzureDevops
  # The connection is missing, disconnected, or switched off at the deployment.
  class IntegrationUnavailable < Error
    def initialize(message = nil, details: nil)
      super(message, code: "integration_unavailable", status: nil, details: details)
    end
  end
end
