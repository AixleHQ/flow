# frozen_string_literal: true

module Oauth
  # Raised when a credential exists but cannot yield a usable token (needs
  # interactive reconnect). Rescued by resolve_server_secrets (no-op inject) in
  # Phase 1; drives session-start preflight in Phase 2.
  class ReauthRequired < StandardError
    attr_reader :credential

    def initialize(credential, msg = "reauthorization required")
      @credential = credential
      super(msg)
    end
  end
end
