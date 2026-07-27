# frozen_string_literal: true

# Credential-vending endpoint for agent containers.
#
# The in-container `credential_process` helper posts here and pipes the response
# straight to the AWS SDK, so the body must be exactly the credential-process JSON
# document with nothing wrapped around it.
#
# Authenticated by a derived per-session key (CloudAuth::SessionKey), not by the
# session's mcp_key. Only a live session vends: a finished one must not be able to mint
# AWS credentials.
#
# Failures are logged here on purpose. The helper's own stderr is discarded by every
# SDK, so this log is the only place a broken connection is visible.
class CloudCredentialsController < ActionController::API
  def create
    session = TerminalSession.find_by(id: request.headers["X-Session-Id"])
    return unauthorized unless session&.active?
    return unauthorized unless CloudAuth::SessionKey.valid?(session, request.headers["X-Cloud-Key"])

    # An auth session must start with nothing connected. Vending a connection made earlier
    # would silently log the user in to the account they are trying to change, and the
    # connect step — which only appears when the helper reports nothing to vend — would never
    # show. A connection made DURING this session is different: that is the user finishing
    # the flow, and vending it is what lets the CLI's own verification pass first time.
    return withhold_preexisting(session) if withhold_from_auth_session?(session)

    render plain: CloudAuth::AwsCredentialVendor.new(user: session.user).to_credential_process_json,
           content_type: "application/json"
  rescue CloudAuth::ExpiredError, CloudAuth::InvalidRegistrationError => e
    fail_with(session, :unauthorized, "reauthorization_required", e)
  rescue CloudAuth::NotConnectedError => e
    # The helper only runs because something asked for AWS credentials — inside an auth
    # container that something is Claude Code's own Bedrock wizard executing
    # credential_process during verification. So this failure is the signal that the user
    # just chose Bedrock in the TUI, and it is what opens the connect step in the browser.
    request_cloud_connect(session)
    fail_with(session, :conflict, "not_connected", e)
  rescue CloudAuth::NotVendableError => e
    fail_with(session, :conflict, "not_connected", e)
  rescue CloudAuth::Error => e
    fail_with(session, :bad_gateway, "provider_error", e)
  end

  private

  def unauthorized
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def withhold_from_auth_session?(session)
    return false unless session.session_type == "auth_setup"

    credential = session.user.agent_credentials.find_by(agent_type: "claude_code")
    return false if credential.nil?

    # Anything last written before this session opened predates it.
    credential.updated_at <= session.created_at
  end

  def withhold_preexisting(session)
    request_cloud_connect(session)
    Rails.logger.info("[CloudCredentials] session=#{session.id} withheld: pre-existing connection in an auth session")
    render json: { error: "not_connected" }, status: :conflict
  end

  # Recorded via update! rather than update_column on purpose: the model's broadcasts_to
  # is what wakes the browser. Set once — the helper retries while it waits, and each
  # write would otherwise be another broadcast.
  def request_cloud_connect(session)
    return if session.metadata&.dig("cloud_connect_requested_at").present?

    session.update!(metadata: (session.metadata || {}).merge("cloud_connect_requested_at" => Time.current.iso8601))
  end

  def fail_with(session, status, code, error)
    Rails.logger.error(
      "[CloudCredentials] session=#{session&.id} #{code}: #{error.class.name.demodulize} #{error.message}"
    )
    render json: { error: code }, status: status
  end
end
