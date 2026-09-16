# frozen_string_literal: true

module AzureDevops
  # The company/installation binding does not authorize this target. Distinct
  # from PermissionDenied: Azure was never asked. An app-only token proves the
  # APPLICATION can reach an organization and proves nothing about who is asking.
  class NotAuthorized < Error
    def initialize(message = nil, details: nil)
      super(message, code: "not_authorized", status: nil, details: details)
    end
  end
end
