# frozen_string_literal: true

# The two public documents Microsoft Entra reads to trust a token this deployment
# signs for a customer's federated identity credential. Entra fetches them
# anonymously and from outside, so there is no session, no CSRF and no
# authentication here; both documents hold only public material.
class OidcIssuerController < ActionController::API
  before_action :require_federation

  def configuration
    publish AzureDevops::FederationConfig.discovery_document
  end

  def jwks
    publish AzureDevops::FederationConfig.jwks
  end

  private

  def require_federation
    head :not_found unless AzureDevops::FederationConfig.enabled?
  end

  # Short, so a key published ahead of a rotation is seen before it is switched to.
  def publish(document)
    expires_in 5.minutes, public: true
    render json: document
  end
end
