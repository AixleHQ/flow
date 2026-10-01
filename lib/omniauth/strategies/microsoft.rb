# frozen_string_literal: true

require "omniauth/entra_id"

module OmniAuth
  module Strategies
    # Entra ID sign-in that can authenticate the app with its certificate held
    # as a PEM private key and a thumbprint — the form a deployment keeps it in,
    # shared with the Azure DevOps integration. omniauth-entra-id itself signs
    # only from a PKCS#12 file on disk.
    class Microsoft < EntraId
      option :name, "microsoft"
      option :private_key, nil
      option :certificate_thumbprint, nil

      def self.configured?(settings)
        settings&.client_id.present? && (settings.private_key.present? || settings.client_secret.present?)
      end

      def client
        if options.private_key.present?
          # The parent takes its certificate branch only when certificate_path
          # is set, and prefers a secret over it. client_assertion below never
          # opens the path.
          options.client_secret = nil
          options.certificate_path = "pem"
          # oauth2 defaults to HTTP Basic client authentication, which would
          # send an empty secret alongside the assertion.
          options.client_options.auth_scheme = :private_key_jwt
        end
        super
      end

      def client_assertion(tenant_id, client_id, _certificate_path)
        ::Entra::ClientAssertion.new(
          client_id: client_id,
          private_key: options.private_key,
          certificate_thumbprint: options.certificate_thumbprint,
          token_url: "#{options.base_url.presence || BASE_URL}/#{tenant_id}/oauth2/v2.0/token"
        ).to_jwt
      end
    end
  end
end
