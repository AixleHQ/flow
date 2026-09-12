# frozen_string_literal: true

module AzureDevops
  # Azure itself refused the operation. Recheckable and target-specific: a 403 on
  # one repository or area path must not disable unrelated targets.
  class PermissionDenied < Error
    def initialize(message = nil, details: nil)
      super(message, code: "permission_denied", status: 403, details: details)
    end
  end
end
