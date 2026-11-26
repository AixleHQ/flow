# frozen_string_literal: true

module AwsOidc
  # One issuer per AWS OIDC integration (docs/design/aws-oidc-integration.md §5.1), so an
  # IAM OIDC provider trusts one project's integration and never every tenant of the
  # instance, even under a trust policy that checks only the audience.
  module Issuer
    PATH_PREFIX = "/oidc"

    module_function

    def url(integration)
      "#{Settings.protocol}://#{Settings.domain}#{path(integration)}"
    end

    def path(integration)
      "#{PATH_PREFIX}/#{integration.aws_oidc_issuer_key}"
    end

    def discovery(integration)
      issuer = url(integration)
      {
        issuer: issuer,
        jwks_uri: "#{issuer}/jwks",
        response_types_supported: %w[id_token],
        subject_types_supported: %w[public],
        id_token_signing_alg_values_supported: %w[RS256],
        claims_supported: %w[iss aud sub iat nbf exp jti]
      }
    end

    # Answers only while the integration is connected: disconnecting is then a kill
    # switch STS enforces, not just Flow.
    def find_active(issuer_key)
      return nil if issuer_key.blank?

      Integration.where(provider: :aws_oidc, status: :active).find_by("settings->>'issuer_key' = ?", issuer_key)
    end
  end
end
