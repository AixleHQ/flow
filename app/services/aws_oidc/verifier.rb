# frozen_string_literal: true

module AwsOidc
  # The integration page's Verify (docs/design/aws-oidc-integration.md §8): assume the role
  # with the integration's own `verify:` subject, ask STS who that is, and drop the
  # credentials. Tags are sent so a trust policy without sts:TagSession fails here and not
  # on the first run.
  class Verifier
    Result = Data.define(:ok, :assumed_role_arn, :failure, :message, :subject)

    def initialize(role:)
      @role = role
    end

    def call
      subject = Subject.for_verify(@role.integration)
      minted = Token.mint(issuer: Issuer.url(@role.integration), subject: subject,
                          tags: { flow_project: @role.integration.project_id, flow_verify: "true" })
      sts = StsClient.new(region: @role.region)
      credentials = sts.assume_role_with_web_identity(role_arn: @role.role_arn, session_name: "flow-verify-#{@role.id}",
                                                      token: minted.token, duration_seconds: 900)
      Result.new(ok: true, assumed_role_arn: sts.caller_arn(credentials: credentials), failure: nil, message: nil,
                 subject: subject)
    rescue Error => e
      Result.new(ok: false, assumed_role_arn: nil, failure: failure_kind(e), message: explain(e, subject),
                 subject: subject)
    end

    private

    def failure_kind(error)
      error.class.name.demodulize.underscore.delete_suffix("_error")
    end

    def explain(error, subject)
      issuer = Issuer.url(@role.integration)
      case error
      when IssuerUnreachableError
        "AWS could not fetch Flow's signing keys from #{issuer}. The issuer must be reachable from the " \
        "internet over HTTPS."
      when IdentityTokenError
        "AWS rejected the token. Check that account #{@role.account_id} has an IAM OIDC provider for " \
        "#{issuer} with audience #{Token::AUDIENCE}. AWS said: #{error.message}"
      when TrustPolicyError
        "The role's trust policy rejected subject #{subject}. It must allow that subject, and allow " \
        "sts:TagSession as well as sts:AssumeRoleWithWebIdentity. AWS said: #{error.message}"
      when RoleConfigurationError
        "AWS refused the request for this role: #{error.message}"
      else
        "AWS STS did not answer: #{error.message}"
      end
    end
  end
end
