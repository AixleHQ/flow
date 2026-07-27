# frozen_string_literal: true

module CloudAuth
  # Server-side AWS IAM Identity Center device flow.
  #
  # The user supplies their Start URL, approves in their own browser, and we keep the
  # OIDC client registration plus the refresh token. Nothing interactive ever happens
  # inside the agent container: it is ephemeral, cannot show a browser, and a credential
  # source running there cannot talk to the user at all (its stderr is discarded).
  # Holding the registration here also means refresh-token portability between machines
  # never becomes a question — we are always the same client.
  #
  # Three calls: #start → #poll (repeatedly) → #finish.
  #
  # In-flight state lives in Rails.cache under an opaque handle, never in the
  # credential: a half-finished flow must not leave a partial credential behind, and
  # the device code is bearer-shaped. The cache TTL tracks the device
  # authorization's own expiry.
  #
  # See docs/research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md.
  class AwsDeviceFlow
    # The in-container credential source. The device flow deliberately does NOT write an
    # [sso-session] block into the container — the container never logs in, it just asks
    # our vending endpoint for the credentials this flow's token can mint.
    CREDENTIAL_PROCESS_PATH = "/usr/local/bin/aixle-aws-creds"
    DEFAULT_PROFILE = "aixle-bedrock"
    OIDC_CLIENT_NAME = "Aixle"
    CACHE_NAMESPACE = "cloud_auth:aws_device_flow"
    # Identity Center device authorizations are short-lived; do not outlive one.
    MAX_FLOW_TTL = 15.minutes

    Pending = Data.define(:interval)
    Started = Data.define(:handle, :verification_uri_complete, :verification_uri, :user_code, :interval, :expires_in)
    Approved = Data.define(:accounts)
    AccountChoice = Data.define(:account_id, :account_name, :roles)

    def initialize(user:, client: nil, catalog_factory: nil)
      @user = user
      @client_override = client
      @catalog_factory = catalog_factory
    end

    # Registers an OIDC client and opens a device authorization. The returned
    # verification_uri_complete must be shown to the user verbatim — it is not
    # constructible, and the documented device.sso.<region> host does not resolve.
    def start(start_url:, sso_region:)
      raise ArgumentError, "start_url is required" if start_url.blank?
      raise ArgumentError, "sso_region is required" if sso_region.blank?

      sso = client(sso_region)
      registration = sso.register_client(client_name: OIDC_CLIENT_NAME)
      device = sso.start_device_authorization(registration: registration, start_url: start_url)

      handle = SecureRandom.urlsafe_base64(32)
      write_state(handle, {
        "user_id" => @user.id,
        "start_url" => start_url,
        "sso_region" => sso_region,
        # stringify: Rails.cache round-trips symbol keys faithfully, so mixing key types
        # here would silently read back as nil.
        "registration" => registration.to_h.stringify_keys,
        "device_code" => device.device_code,
        "interval" => device.interval
      }, ttl: flow_ttl(device.expires_in))

      Started.new(
        handle: handle,
        verification_uri_complete: device.verification_uri_complete,
        verification_uri: device.verification_uri,
        user_code: device.user_code,
        interval: device.interval,
        expires_in: device.expires_in
      )
    end

    # Pending while the user has not approved yet. On approval, enumerates the accounts
    # and roles their permission sets grant, so the caller can offer a choice (or skip
    # it when there is exactly one pair).
    def poll(handle:)
      state = read_state!(handle)
      return Approved.new(accounts: deserialize_accounts(state["accounts"])) if state["accounts"]

      sso = client(state["sso_region"])
      registration = registration_from(state)
      token = sso.create_token(registration: registration, device_code: state["device_code"])
      return Pending.new(interval: state["interval"] || 5) if token.nil?

      accounts = enumerate_accounts(sso, token.access_token)
      state = state.merge(
        "token" => token.to_h.stringify_keys,
        "accounts" => accounts.map { |a| a.to_h.stringify_keys }
      )
      # Drop the device code once redeemed — it is single-use and has no further value.
      state.delete("device_code")
      write_state(handle, state, ttl: MAX_FLOW_TTL)

      Approved.new(accounts: accounts)
    end

    # Commits the connection onto the user's existing claude_code credential, merging
    # rather than replacing so a subscription or API-key login already stored there
    # survives. Returns the AgentCredential.
    def finish(handle:, account_id:, role_name:, region:, profile: DEFAULT_PROFILE)
      state = read_state!(handle)
      token = state["token"]
      raise Error, "authorization is not complete" if token.blank?
      raise ArgumentError, "region is required" if region.blank?

      unless permitted?(state, account_id, role_name)
        raise DeniedError, "account #{account_id} / role #{role_name} was not granted by this authorization"
      end

      credential = persist!(state, token, account_id: account_id, role_name: role_name,
                                          region: region, profile: profile)
      delete_state(handle)
      credential
    end

    def cancel(handle:)
      delete_state(handle)
    end

    private

    def client(region)
      @client_override || AwsSsoClient.new(region: region)
    end

    def enumerate_accounts(sso, access_token)
      sso.list_accounts(access_token: access_token).map do |account|
        AccountChoice.new(
          account_id: account.account_id,
          account_name: account.account_name,
          roles: sso.list_account_roles(access_token: access_token, account_id: account.account_id)
        )
      end
    end

    # Never take the caller's word for which account/role to bind: only pairs this
    # authorization actually enumerated are acceptable.
    def permitted?(state, account_id, role_name)
      deserialize_accounts(state["accounts"]).any? do |account|
        account.account_id == account_id && account.roles.include?(role_name)
      end
    end

    def deserialize_accounts(raw)
      (raw || []).map do |a|
        AccountChoice.new(account_id: a["account_id"], account_name: a["account_name"], roles: a["roles"] || [])
      end
    end

    def registration_from(state)
      r = state.fetch("registration")
      AwsSsoClient::Registration.new(
        client_id: r["client_id"],
        client_secret: r["client_secret"],
        expires_at: r["expires_at"]
      )
    end

    def persist!(state, token, account_id:, role_name:, region:, profile:)
      credential = AgentCredential.find_or_initialize_by(user: @user, agent_type: "claude_code")
      current = credential.persisted? ? credential.config_data : {}

      # Connecting Bedrock makes it the inference credential, so any Anthropic-side login is
      # dropped — Claude Code would ignore it anyway, and keeping it makes the active
      # provider unknowable. The design token is left alone: it authorizes separately.
      current = Agents::ClaudeCodeAdapter.new.keep_single_inference(
        current, Agents::ClaudeCodeAdapter::BEDROCK_KEY
      )

      # A model pinned against the previous account does not exist in a new one, and
      # resolve_model would launch sessions on it until someone noticed. The block below is
      # built fresh, so its own pins are already gone; this clears the separate default the
      # user chose in our UI. Same account and role → keep their choice.
      previous = current.dig(Agents::ClaudeCodeAdapter::BEDROCK_KEY, "identity_center") || {}
      if previous["account_id"] != account_id || previous["role_name"] != role_name
        credential.metadata = (credential.metadata || {}).except("default_model")
      end

      credential.config_data = current.merge(
        Agents::ClaudeCodeAdapter::BEDROCK_KEY => {
          "region" => region,
          "profile" => profile,
          "credential_process" => CREDENTIAL_PROCESS_PATH,
          # Narrows Claude Code's own /model picker to what this account can actually invoke,
          # newest first and without the surcharged legacy generation. Refreshed on every
          # reconnect, so a newly enabled model appears after reconnecting.
          "available_models" => available_models(state, token, account_id, role_name, region),
          # Server-side only. Deliberately NOT under "sso_session": that key makes the
          # adapter render an [sso-session] block for the in-container fallback, and this
          # path must never put login material in the container.
          "identity_center" => {
            "start_url" => state["start_url"],
            "sso_region" => state["sso_region"],
            "account_id" => account_id,
            "role_name" => role_name,
            "registration" => state["registration"],
            "token" => token
          }
        }
      )
      credential.save!
      credential
    end

    # Asked with the credentials this authorization just produced, so it reflects the account
    # being bound rather than whatever was connected before. Never fatal: a permission set
    # without bedrock:ListInferenceProfiles is common, and nil simply leaves Claude Code's own
    # picker unrestricted.
    def available_models(state, token, account_id, role_name, region)
      creds = client(state["sso_region"]).role_credentials(
        access_token: token["access_token"], account_id: account_id, role_name: role_name
      )
      args = {
        region: region,
        access_key_id: creds.access_key_id,
        secret_access_key: creds.secret_access_key,
        session_token: creds.session_token
      }
      catalog = @catalog_factory ? @catalog_factory.call(**args) : AwsModelCatalog.new(**args)
      profiles = catalog.inference_profiles

      models = Agents::ClaudeCodeAdapter.new.usable_bedrock_profiles(profiles).map(&:model_id)
      models.presence
    rescue Error => e
      Rails.logger.warn("[AwsDeviceFlow] could not list models for #{account_id}: #{e.message}")
      nil
    end

    # -- in-flight state -------------------------------------------------------

    def flow_ttl(expires_in)
      seconds = expires_in.to_i
      seconds.positive? ? [ seconds.seconds, MAX_FLOW_TTL ].min : MAX_FLOW_TTL
    end

    def cache_key(handle)
      "#{CACHE_NAMESPACE}:#{handle}"
    end

    def write_state(handle, state, ttl:)
      Rails.cache.write(cache_key(handle), state, expires_in: ttl)
    end

    def read_state!(handle)
      state = Rails.cache.read(cache_key(handle))
      raise ExpiredError, "device authorization is no longer in progress" if state.blank?
      # A handle is unguessable, but bind it to its owner anyway so a leaked handle
      # cannot be redeemed onto a different account.
      raise DeniedError, "handle does not belong to this user" unless state["user_id"] == @user.id

      state
    end

    def delete_state(handle)
      Rails.cache.delete(cache_key(handle))
    end
  end
end
