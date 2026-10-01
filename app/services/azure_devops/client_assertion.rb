# frozen_string_literal: true

module AzureDevops
  class ClientAssertion
    def initialize(app:, tenant_id:)
      @app = app
      @tenant_id = tenant_id
    end

    def to_jwt
      Entra::ClientAssertion.new(
        client_id: @app.client_id,
        private_key: @app.private_key,
        certificate_thumbprint: @app.certificate_thumbprint,
        token_url: "#{AppConfig.login_host}/#{@tenant_id}/oauth2/v2.0/token"
      ).to_jwt
    rescue Entra::ClientAssertion::InvalidCredential => e
      raise CredentialActionRequired, "Azure DevOps app #{e.message}"
    end
  end
end
