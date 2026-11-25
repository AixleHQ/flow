# frozen_string_literal: true

module AwsOidc
  # App-owned seam over the two STS calls AWS OIDC makes. Tests stub this class with
  # FakeAwsOidcStsClient and never touch Aws::STS (docs/testing.md R2/R3); vendor errors
  # come out as AwsOidc errors.
  class StsClient
    Credentials = Data.define(:access_key_id, :secret_access_key, :session_token, :expiration, :assumed_role_arn)

    ERRORS = {
      "IDPCommunicationError" => IssuerUnreachableError,
      "InvalidIdentityToken" => IdentityTokenError,
      "IDPRejectedClaim" => IdentityTokenError,
      "ExpiredTokenException" => IdentityTokenError,
      "AccessDenied" => TrustPolicyError,
      "ValidationError" => RoleConfigurationError
    }.freeze

    def initialize(region:)
      raise ArgumentError, "region is required" if region.blank?

      @region = region
    end

    def assume_role_with_web_identity(role_arn:, session_name:, token:, duration_seconds:)
      resp = unsigned_client.assume_role_with_web_identity(
        role_arn: role_arn, role_session_name: session_name, web_identity_token: token,
        duration_seconds: duration_seconds
      )
      creds = resp.credentials
      Credentials.new(access_key_id: creds.access_key_id, secret_access_key: creds.secret_access_key,
                      session_token: creds.session_token, expiration: creds.expiration,
                      assumed_role_arn: resp.assumed_role_user.arn)
    rescue ::Aws::STS::Errors::ServiceError, ::Seahorse::Client::NetworkingError => e
      raise translate(e)
    end

    def caller_arn(credentials:)
      aws_credentials = ::Aws::Credentials.new(credentials.access_key_id, credentials.secret_access_key,
                                               credentials.session_token)
      ::Aws::STS::Client.new(region: @region, credentials: aws_credentials).get_caller_identity.arn
    rescue ::Aws::STS::Errors::ServiceError, ::Seahorse::Client::NetworkingError => e
      raise translate(e)
    end

    private

    # AssumeRoleWithWebIdentity is unsigned: the token is the credential. `credentials: nil`
    # is how the SDK's own AssumeRoleWebIdentityCredentials builds this client; `false`
    # breaks its client-metrics plugin.
    def unsigned_client
      @unsigned_client ||= ::Aws::STS::Client.new(region: @region, credentials: nil)
    end

    def translate(error)
      code = error.respond_to?(:code) ? error.code : nil
      klass = ERRORS.fetch(code.to_s, ProviderError)
      klass.new(error.message, aws_code: code)
    end
  end
end
