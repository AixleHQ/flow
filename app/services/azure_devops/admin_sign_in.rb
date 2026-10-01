# frozen_string_literal: true

module AzureDevops
  # "Sign in with Microsoft" for the administrator connecting an organization:
  # the authorization-code flow of Aixle's own multi-tenant Entra application,
  # for a delegated Azure DevOps token. It replaces pasting an administrator
  # PAT, and its consent screen also creates the application's service
  # principal in the customer's directory — the step `az ad sp create` did.
  #
  # The token proves control exactly the way a PAT did (Onboarding) and is
  # just as short-lived: held encrypted in the cache for the few minutes
  # between the redirect back and choosing projects, then gone.
  module AdminSignIn
    PROVIDER = "azure_devops"
    # Azure DevOps' resource id; user_impersonation is its delegated permission.
    SCOPE = "499b84ac-1321-427f-aa17-267ca6975798/user_impersonation"
    HOLD = 15.minutes

    module_function

    # Signs in against the organization's own directory, so an account from
    # another one is not even offered.
    def authorize_url(project:, user:, organization:)
      tenant = TenantDiscovery.call(organization)
      app = AppConfig.fetch("default")
      app.validate!
      verifier = SecureRandom.urlsafe_base64(48)
      state = ::Oauth::State.encode(
        owner_type: "Project", owner_id: project.id, user_id: user.id, return_to: nil, code_verifier: verifier,
        provider: PROVIDER, context: { "organization" => tenant.organization, "tenant_id" => tenant.tenant_id }
      )
      query = URI.encode_www_form(
        client_id: app.client_id, response_type: "code", redirect_uri: redirect_uri, response_mode: "query",
        scope: SCOPE, state: state, prompt: "select_account",
        code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
        code_challenge_method: "S256"
      )
      "#{AppConfig.login_host}/#{ERB::Util.url_encode(tenant.tenant_id)}/oauth2/v2.0/authorize?#{query}"
    end

    def redirect_uri
      "#{Settings.protocol}://#{Settings.domain}/integrations/azure_devops/oauth/callback"
    end

    def exchange!(code:, tenant_id:, code_verifier:)
      app = AppConfig.fetch("default")
      response = http.post("/#{ERB::Util.url_encode(tenant_id)}/oauth2/v2.0/token") do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          { grant_type: "authorization_code", client_id: app.client_id, code: code.to_s, redirect_uri: redirect_uri,
            scope: SCOPE, code_verifier: code_verifier.to_s }.merge(client_authentication(app, tenant_id))
        )
      end
      body = parse(response)
      return AdminCredential.sign_in(body["access_token"]) if response.status == 200 && body["access_token"].present?

      description = body["error_description"].to_s.lines.first.to_s.strip.truncate(300)
      raise NotAuthorized, "Microsoft did not complete the sign-in (#{body['error'].presence || response.status}): #{description}"
    rescue Faraday::Error => e
      raise Error.new("Microsoft's sign-in endpoint did not answer (#{e.class})", code: "token_endpoint_unreachable")
    end

    # A handle for the browser to come back with; the token itself never
    # leaves the server.
    def hold(credential, user:, organization:)
      handle = SecureRandom.urlsafe_base64(24)
      payload = { "token" => credential.secret, "user_id" => user.id, "organization" => organization.to_s.downcase }
      Rails.cache.write(cache_key(handle), encryptor.encrypt_and_sign(payload, expires_in: HOLD), expires_in: HOLD)
      handle
    end

    # The held sign-in for this user and organization, or nil once it has
    # expired, been used up, or belongs to someone else.
    def fetch(handle, user:, organization:)
      return if handle.blank?

      payload = encryptor.decrypt_and_verify(Rails.cache.read(cache_key(handle)).to_s)
      return unless payload.is_a?(Hash) && payload["user_id"] == user.id
      return unless payload["organization"] == organization.to_s.strip.downcase

      AdminCredential.sign_in(payload["token"])
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      nil
    end

    def release(handle)
      Rails.cache.delete(cache_key(handle)) if handle.present?
    end

    def client_authentication(app, tenant_id)
      case app.credential_kind
      when :certificate
        { client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
          client_assertion: ClientAssertion.new(app: app, tenant_id: tenant_id).to_jwt }
      when :client_secret then { client_secret: app.client_secret }
      else raise CredentialActionRequired, "No usable Azure DevOps app credential"
      end
    end

    def parse(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end

    def cache_key(handle) = "azure_devops:admin_sign_in:#{Digest::SHA256.hexdigest(handle.to_s)}"

    def encryptor
      secret = Rails.application.key_generator.generate_key("azure_devops admin sign-in", ActiveSupport::MessageEncryptor.key_len)
      ActiveSupport::MessageEncryptor.new(secret)
    end

    def http
      Faraday.new(url: AppConfig.login_host) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        f.adapter Faraday.default_adapter
      end
    end
  end
end
