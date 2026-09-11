# frozen_string_literal: true

module AzureDevops
  # One error family for the whole adapter, so callers (tool handlers, the Git
  # credential endpoint, the connection UI) can branch on a stable `code`
  # instead of on a provider message. Codes match §10 of the design.
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

  # The deployment has no usable app credential, or the one it has was rejected
  # by Entra. An operator fixes this; never tell a user to sign in again.
  class CredentialActionRequired < Error
    def initialize(message = nil, details: nil)
      super(message, code: "credential_action_required", details: details)
    end
  end

  # The company/installation binding does not authorize this target. Distinct
  # from permission_denied: Azure was never asked.
  class NotAuthorized < Error
    def initialize(message = nil, details: nil)
      super(message, code: "not_authorized", details: details)
    end
  end

  class IntegrationUnavailable < Error
    def initialize(message = nil, details: nil)
      super(message, code: "integration_unavailable", details: details)
    end
  end

  class PermissionDenied < Error
    def initialize(message = nil, details: nil)
      super(message, code: "permission_denied", status: 403, details: details)
    end
  end

  class NotFound < Error
    def initialize(message = nil, details: nil)
      super(message, code: "not_found_or_inaccessible", status: 404, details: details)
    end
  end

  class ValidationFailed < Error
    def initialize(message = nil, details: nil)
      super(message, code: "validation_failed", status: 400, details: details)
    end
  end

  class Conflict < Error
    def initialize(message = nil, details: nil)
      super(message, code: "conflict", status: 409, details: details)
    end
  end

  class RateLimited < Error
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil)
      super(message, code: "rate_limited", status: 429)
      @retry_after = retry_after
    end
  end

  # The request left Aixle and its outcome was never observed. Deliberately not
  # a failure: the recovery path is a read, never another write.
  class OutcomeUnknown < Error
    def initialize(message = nil, details: nil)
      super(message, code: "outcome_unknown", details: details)
    end
  end
end
