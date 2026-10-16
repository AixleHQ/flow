# frozen_string_literal: true

module Bitbucket
  # The adapter's error family. Callers branch on `code`, never on Bitbucket's
  # wording; the codes are the ones PullRequests::Error and the Azure adapter use.
  class Error < StandardError
    attr_reader :code, :status, :details

    def initialize(message = nil, code: "bitbucket_error", status: nil, details: nil)
      super(message || code.to_s)
      @code = code.to_s
      @status = status
      @details = details
    end

    def to_h
      { error: code, message: message, details: details }.compact
    end

    # No such entity, or this identity cannot see it — one code, so a refusal
    # never confirms that something hidden exists.
    class NotFound < Error
      def initialize(message = nil, details: nil)
        super(message, code: "not_found_or_inaccessible", status: 404, details: details)
      end
    end

    class NotAuthorized < Error
      def initialize(message = nil) = super(message, code: "not_authorized", status: 401)
    end

    class PermissionDenied < Error
      def initialize(message = nil) = super(message, code: "permission_denied", status: 403)
    end

    class ValidationFailed < Error
      def initialize(message = nil, details: nil)
        super(message, code: "validation_failed", status: 400, details: details)
      end
    end

    class Conflict < Error
      def initialize(message = nil, details: nil) = super(message, code: "conflict", status: 409, details: details)
    end

    class RateLimited < Error
      attr_reader :retry_after

      def initialize(message = nil, retry_after: nil)
        super(message, code: "rate_limited", status: 429, details: ({ retry_after: retry_after } if retry_after))
        @retry_after = retry_after
      end
    end

    # A write left Aixle and no answer came back. Reissuing it blindly is how
    # duplicate pull requests and comments get made.
    class OutcomeUnknown < Error
      def initialize(message = nil) = super(message, code: "outcome_unknown")
    end

    # Nothing to authenticate with: the app has not delivered a usable token, or
    # the connection lost its installation.
    class CredentialUnavailable < Error
      def initialize(message = nil) = super(message, code: "integration_unavailable")
    end
  end
end
