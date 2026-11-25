# frozen_string_literal: true

module AwsOidc
  # Hands a workflow step's session one-hour credentials for an attached role
  # (docs/design/aws-oidc-integration.md §6). The container's credential_process helper
  # asks; Rails signs a token, spends it on STS in the same request and returns the
  # credentials. The token never leaves this process.
  class CredentialVendor
    # Several SDK clients in one container resolve at once, and each asks again near
    # expiry. Within this margin a fresh exchange is made; before it, the last one is
    # handed out again.
    REFRESH_SKEW = 5.minutes

    def initialize(session:, role_name:)
      @session = session
      @role_name = role_name.to_s
    end

    def call
      role = entitled_role!
      issuance = single_flight(role) { reusable_issuance(role) || exchange!(role) }
      arm_redaction!
      issuance
    end

    def to_credential_process_json
      issuance = call
      secrets = issuance.secrets
      {
        "Version" => 1,
        "AccessKeyId" => issuance.access_key_id,
        "SecretAccessKey" => secrets["secret_access_key"],
        "SessionToken" => secrets["session_token"],
        "Expiration" => issuance.expires_at.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      }.to_json
    end

    private

    attr_reader :session, :role_name

    def entitled_role!
      raise NotEntitledError, "only an active workflow step may assume an AWS role" unless step_session?

      role = AwsOidcRole.for_project(session.project)
                        .where(id: SessionConfigResolver.new(session).resolve_aws_oidc_role_ids)
                        .find_by(name: role_name)
      raise NotEntitledError, "AWS role #{role_name.inspect} is not attached to this step" if role.nil?

      raise NotEntitledError, "the project's AWS OIDC integration is not connected" unless role.integration.active?

      role
    end

    def step_session?
      session.active? && session.workflow_step? && session.step_run&.step.present?
    end

    def reusable_issuance(role)
      AwsOidcCredentialIssuance.for_session(session)
                               .where(aws_oidc_role_id: role.id, expires_at: REFRESH_SKEW.from_now..)
                               .order(created_at: :desc).first
    end

    def exchange!(role)
      step_run = session.step_run
      subject = Subject.for_step(step_run.step)
      minted = Token.mint(issuer: Issuer.url(role.integration), subject: subject, tags: tags(step_run))
      credentials = StsClient.new(region: role.region).assume_role_with_web_identity(
        role_arn: role.role_arn, session_name: "flow-session-#{session.id}", token: minted.token,
        duration_seconds: role.session_duration_seconds
      )

      AwsOidcCredentialIssuance.create!(
        aws_oidc_role: role, project: session.project, terminal_session: session, step_run: step_run,
        user: session.user, role_name: role.name, role_arn: role.role_arn, subject: subject, jti: minted.jti,
        access_key_id: credentials.access_key_id, expires_at: credentials.expiration,
        secrets: { secret_access_key: credentials.secret_access_key, session_token: credentials.session_token }
      )
    end

    def tags(step_run)
      {
        flow_project: session.project_id, flow_workflow: step_run.workflow_run.workflow_id,
        flow_step: step_run.step_id, flow_run: step_run.workflow_run_id, flow_session: session.id,
        flow_user: session.user_id
      }.compact
    end

    # The list the container's log filters read must hold these values before they are
    # handed out: a value that reaches a log ahead of its entry cannot be taken back
    # (same rule as InternalTools::GetConfigItem).
    def arm_redaction!
      return if Sessions::SecretRegistry.publish!(session)

      raise ProviderError, "this session's log redaction could not be armed; credentials were not returned"
    end

    def single_flight(role, &)
      AwsOidcCredentialIssuance.transaction do
        AwsOidcCredentialIssuance.connection.execute(
          ActiveRecord::Base.sanitize_sql_array(
            [ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", "aws_oidc:#{session.id}:#{role.id}" ]
          )
        )
        yield
      end
    end
  end
end
