# frozen_string_literal: true

module CloudAuth
  # Mints short-lived AWS credentials for a connected Identity Center account.
  #
  # This is what the in-container `credential_process` helper calls. The container holds
  # no AWS material of its own: it asks, we exchange the stored refresh token for role
  # credentials, and it gets a JSON blob that expires within the hour.
  #
  # Takes the credential, not a user: credentials are per (user, company) and the
  # caller — a session via SessionCompany, or the profile page via the current
  # company — is the only layer that can say which company is being billed.
  #
  # Refresh is single-flight under a row lock and never downgrades a fresher token —
  # same discipline as Oauth::TokenService#fresh, for the same reason: several sessions
  # of one user can resolve credentials at the same moment.
  #
  # See docs/research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md.
  class AwsCredentialVendor
    # Refresh the Identity Center access token this far before it expires. The token is
    # hourly, and this only needs to cover one GetRoleCredentials round-trip.
    REFRESH_SKEW = 5.minutes

    Vended = Data.define(:access_key_id, :secret_access_key, :session_token, :expiration)

    def initialize(credential:, client: nil)
      @credential = credential
      @client_override = client
    end

    def call
      credential = @credential
      raise NotConnectedError, "no claude_code credential for this company" if credential.nil?

      block = bedrock_block!(credential)
      unless identity_center?(block)
        # A key entered in Claude Code's own wizard needs no vending — the container already
        # carries it in its env.
        raise NotVendableError, "this AWS connection does not need server-side vending"
      end

      vend_via_identity_center(credential, block["identity_center"])
    end

    # The exact shape the AWS SDK credential-process provider expects. Two details are
    # load-bearing: `Version` must be the unquoted integer 1 (every SDK rejects "1"),
    # and `Expiration` must be strict RFC 3339 with a Z — Go's json decoder accepts
    # nothing looser. Omitting Expiration would make the SDK treat these as long-term
    # and never re-invoke the helper at all.
    def to_credential_process_json
      vended = call
      {
        "Version" => 1,
        "AccessKeyId" => vended.access_key_id,
        "SecretAccessKey" => vended.secret_access_key,
        "SessionToken" => vended.session_token,
        "Expiration" => vended.expiration.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      }.to_json
    end

    private

    def client(region)
      @client_override || AwsSsoClient.new(region: region)
    end

    def bedrock_block!(credential)
      block = credential.config_data[Agents::ClaudeCodeAdapter::BEDROCK_KEY]
      raise NotConnectedError, "no AWS connection on this credential" unless block.is_a?(Hash)

      block
    end

    def identity_center?(block)
      idc = block["identity_center"]
      idc.is_a?(Hash) && idc["account_id"].present? && idc["role_name"].present?
    end

    def vend_via_identity_center(credential, idc)
      access_token = fresh_access_token(credential, idc)
      creds = client(idc["sso_region"]).role_credentials(
        access_token: access_token,
        account_id: idc.fetch("account_id"),
        role_name: idc.fetch("role_name")
      )
      vended(creds)
    end

    # RoleSessionName is the platform user id on purpose: it lands in the customer's
    # CloudTrail and in CUR 2.0's line_item_iam_principal, which is per-user cost
    # attribution with nothing to manage.
    def vended(creds)
      Vended.new(
        access_key_id: creds.access_key_id,
        secret_access_key: creds.secret_access_key,
        session_token: creds.session_token,
        expiration: creds.expiration
      )
    end

    def identity_center!(credential)
      idc = bedrock_block!(credential)["identity_center"]
      raise NotVendableError, "this AWS connection does not use Identity Center" unless idc.is_a?(Hash)

      idc
    end

    def fresh_access_token(credential, idc)
      token = idc["token"] || {}
      return token["access_token"] if token["access_token"].present? && !expiring?(token)

      refresh!(credential)
    end

    def expiring?(token)
      expires_at = token["expires_at"]
      return true if expires_at.blank?

      # Time.zone.parse returns nil for unparseable input rather than raising, so the
      # rescue alone is not enough. Anything we cannot read counts as expiring.
      parsed = Time.zone.parse(expires_at.to_s)
      parsed.nil? || parsed <= REFRESH_SKEW.from_now
    rescue ArgumentError, TypeError
      true
    end

    def refresh!(credential)
      access_token = nil

      credential.with_lock do
        # Re-read inside the lock: another session of the same user may have refreshed
        # while we waited, in which case there is nothing to do.
        idc = identity_center!(credential.reload)
        token = idc["token"] || {}

        if token["access_token"].present? && !expiring?(token)
          access_token = token["access_token"]
        else
          refreshed = exchange_refresh_token(idc, token)
          persist_token!(credential, refreshed, previous: token)
          access_token = refreshed.access_token
        end
      end

      access_token
    end

    def exchange_refresh_token(idc, token)
      registration = idc["registration"] || {}
      raise InvalidRegistrationError, "no client registration stored" if registration["client_id"].blank?
      if registration["expires_at"].present? && Time.zone.parse(registration["expires_at"].to_s) <= Time.current
        # Identity Center caps registrations at 90 days and refresh cannot cross that
        # boundary — only a fresh device flow recovers.
        raise InvalidRegistrationError, "client registration has expired; re-authorisation required"
      end
      raise ExpiredError, "no refresh token stored" if token["refresh_token"].blank?

      client(idc["sso_region"]).refresh_token(
        registration: AwsSsoClient::Registration.new(
          client_id: registration["client_id"],
          client_secret: registration["client_secret"],
          expires_at: registration["expires_at"]
        ),
        refresh_token: token["refresh_token"]
      )
    end

    # Never clobber a refresh token with nothing: Identity Center may omit it on a
    # refresh response, and losing it would end the connection silently.
    def persist_token!(credential, refreshed, previous:)
      config = credential.config_data
      bedrock = config.fetch(Agents::ClaudeCodeAdapter::BEDROCK_KEY)
      bedrock["identity_center"]["token"] = {
        "access_token" => refreshed.access_token,
        "refresh_token" => refreshed.refresh_token.presence || previous["refresh_token"],
        "expires_at" => refreshed.expires_at.iso8601
      }
      credential.config_data = config
      credential.save!
    end
  end
end
