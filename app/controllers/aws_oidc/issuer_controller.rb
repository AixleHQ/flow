# frozen_string_literal: true

# The OpenID Connect discovery document and JWKS of an AWS OIDC integration's issuer
# (docs/design/aws-oidc-integration.md §5.1). Public: AWS STS fetches both without
# credentials. 404 for an unknown, disconnected or flag-off integration.
class AwsOidc::IssuerController < ActionController::API
  before_action :load_integration

  def discovery
    expires_in 5.minutes, public: true
    render json: AwsOidc::Issuer.discovery(@integration)
  end

  def jwks
    expires_in 5.minutes, public: true
    render json: AwsOidc::SigningKeys.jwks
  end

  private

  def load_integration
    @integration = AwsOidc::Issuer.find_active(params[:issuer_key])
    head :not_found if @integration.nil?
  end
end
