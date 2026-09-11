# frozen_string_literal: true

module AzureDevops
  # The deployment has no usable app credential, or Entra rejected the one it
  # has. An operator fixes this — never tell a user to sign in again, because
  # there is no user credential in this flow to renew.
  class CredentialActionRequired < Error
    def initialize(message = nil, details: nil)
      super(message, code: "credential_action_required", status: nil, details: details)
    end
  end
end
