# frozen_string_literal: true

module AzureDevops
  # Entra refused the assertion this deployment signed for a customer-owned app.
  # Unlike CredentialActionRequired the fix is on the customer's side: their
  # federated credential, client id or app registration. The message names the
  # most likely cause, because Entra accepts a mistyped subject when it is saved
  # and only refuses the exchange later.
  class FederationRejected < Error
    def initialize(message = nil, details: nil)
      super(message, code: "federation_rejected", status: nil, details: details)
    end
  end
end
