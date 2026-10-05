# frozen_string_literal: true

module Teams
  # Binding a Microsoft 365 organization to an Aixle company
  # (docs/design/teams-integration.md §6.2). An admin of the company asks for it
  # and gets an approval link; a directory administrator of the organization
  # opens it and signs in with Microsoft. The tenant comes from that sign-in's
  # token, never from a parameter, and one tenant belongs to one company.
  module Connection
    class Refused < StandardError; end

    PROVIDER = "teams"
    APPROVAL_TTL = 7.days
    # Directory roles that can decide which apps an organization uses, by
    # Microsoft's built-in role template id: the same in every tenant, and what a
    # sign-in's `wids` claim lists. Not secrets. Source:
    # https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#all-roles
    ADMIN_ROLES = {
      "62e90394-69f5-4237-9190-012177145e10" => "Global Administrator",
      "e8611ab8-c189-46e8-94e1-60213ab1f814" => "Privileged Role Administrator",
      "158c047a-c907-4556-b7ef-446551a6b5f7" => "Cloud Application Administrator",
      "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3" => "Application Administrator",
      "69091246-20e8-4a56-aa4d-066075b2a7a8" => "Teams Administrator"
    }.freeze
    FILES_ROLE = "Files.ReadWrite.All"

    module_function

    # A pending connection for the company and the link that approves it. The
    # link is shown once; only its digest is kept.
    def start!(company:, user:)
      integration = Integration.where(provider: PROVIDER, company: company, status: "inactive")
                               .find { |candidate| candidate.settings.to_h["tenant_id"].blank? } ||
                    Integration.new(provider: PROVIDER, company: company, project: nil, name: "Microsoft Teams")
      token = SecureRandom.urlsafe_base64(32)
      integration.assign_attributes(connected_by: user, status: "inactive", settings: integration.settings.to_h.merge(
        "approval_digest" => digest(token), "approval_expires_at" => APPROVAL_TTL.from_now.iso8601
      ))
      integration.save!
      [ integration, token ]
    end

    def approval_url(token)
      "#{Settings.protocol}://#{Settings.domain}/integrations/teams/approve/#{token}"
    end

    def find_by_token(token)
      return nil if token.blank?

      integration = Integration.where(provider: PROVIDER).find_by("settings->>'approval_digest' = ?", digest(token))
      return nil if integration.nil?
      return nil if Time.zone.parse(integration.settings.to_h["approval_expires_at"].to_s).to_i < Time.current.to_i

      integration
    end

    def authorize_url(integration)
      verifier = SecureRandom.urlsafe_base64(48)
      state = ::Oauth::State.encode(owner_type: "Integration", owner_id: integration.id, user_id: nil, return_to: nil,
                                    code_verifier: verifier, provider: PROVIDER)
      query = URI.encode_www_form(
        client_id: Config.app_id, response_type: "code", redirect_uri: redirect_uri, response_mode: "query",
        scope: "openid profile", state: state, prompt: "select_account",
        code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
        code_challenge_method: "S256"
      )
      "#{Config.cloud[:login]}/organizations/oauth2/v2.0/authorize?#{query}"
    end

    def redirect_uri = "#{Settings.protocol}://#{Settings.domain}/integrations/teams/callback"
    def file_access_redirect_uri = "#{Settings.protocol}://#{Settings.domain}/integrations/teams/file_access/callback"

    # Exchanges the sign-in for its ID token and binds the organization it names.
    def complete!(integration:, code:, code_verifier:)
      claims = sign_in_claims(code, code_verifier)
      roles = Array(claims["wids"]) & ADMIN_ROLES.keys
      if roles.empty?
        raise Refused, "#{claims['name'] || 'This account'} is not an administrator of its Microsoft 365 organization. " \
                       "A Global, Privileged Role, Cloud Application, Application or Teams Administrator has to approve."
      end

      bind!(integration, claims, roles)
    end

    def bind!(integration, claims, roles)
      tenant_id = claims["tid"].to_s
      raise Refused, "Microsoft did not say which organization this is" unless tenant_id.match?(Config::GUID)
      if Config.allowed_tenant_ids.any? && Config.allowed_tenant_ids.exclude?(tenant_id)
        raise Refused, "This Aixle installation does not serve that Microsoft 365 organization"
      end

      ActiveRecord::Base.transaction do
        endpoint = WebhookEndpoint.find_by(slug: endpoint_slug(tenant_id))
        if endpoint && endpoint.config.to_h["integration_id"] != integration.id
          raise Refused, "That Microsoft 365 organization is already connected to an Aixle workspace"
        end

        endpoint ||= WebhookEndpoint.create!(slug: endpoint_slug(tenant_id), provider: :teams, company: integration.company,
                                             project: nil, verification_strategy: :none, secret: nil,
                                             config: { "integration_id" => integration.id })
        endpoint.update!(enabled: true)
        integration.update!(status: "active", name: "Microsoft Teams (#{domain_of(claims) || tenant_id})",
                            settings: integration.settings.to_h.merge(
                              "tenant_id" => tenant_id, "tenant_domain" => domain_of(claims),
                              "approved_by" => { "object_id" => claims["oid"], "name" => claims["name"],
                                                 "username" => claims["preferred_username"],
                                                 "roles" => roles.map { |r| ADMIN_ROLES[r] } },
                              "approved_at" => Time.current.iso8601
                            ))
      end
      integration
    rescue ActiveRecord::RecordNotUnique
      raise Refused, "That Microsoft 365 organization is already connected to an Aixle workspace"
    end

    # Microsoft's admin-consent page for the file permission; only a directory
    # administrator can complete it, and it grants nothing until one does.
    def file_access_url(integration)
      state = ::Oauth::State.encode(owner_type: "Integration", owner_id: integration.id, user_id: nil, return_to: nil,
                                    code_verifier: nil, provider: "teams_file_access")
      query = URI.encode_www_form(client_id: Config.app_id, redirect_uri: file_access_redirect_uri, state: state)
      "#{Config.cloud[:login]}/#{integration.settings.to_h['tenant_id']}/adminconsent?#{query}"
    end

    # Asks Entra what the grant now is. A token's roles are fixed when it is
    # issued, so the cached one is dropped first: it predates the consent.
    def confirm_file_access!(integration)
      tenant_id = integration.settings.to_h["tenant_id"]
      TokenService.forget!(tenant_id)
      roles = JWT.decode(TokenService.graph_token(tenant_id), nil, false).first["roles"]
      granted = Array(roles).include?(FILES_ROLE)
      integration.update!(settings: integration.settings.to_h.merge("file_access" => granted,
                                                                    "file_access_checked_at" => Time.current.iso8601))
      granted
    end

    def endpoint_slug(tenant_id) = "teams-tenant-#{tenant_id}"

    def digest(token) = Digest::SHA256.hexdigest(token.to_s)

    def domain_of(claims) = claims["preferred_username"].to_s.split("@", 2)[1].presence

    # The ID token arrives straight from Entra's token endpoint over TLS, in
    # exchange for a code only this app's credential can redeem, so its claims
    # are Entra's (OpenID Connect Core §3.1.3.7) and are read without a signature
    # check; what is still checked is that it was issued to this app, for a
    # directory, and is current.
    def sign_in_claims(code, code_verifier)
      url = "#{Config.cloud[:login]}/organizations/oauth2/v2.0/token"
      form = { grant_type: "authorization_code", client_id: Config.app_id, code: code.to_s, redirect_uri: redirect_uri,
               scope: "openid profile", code_verifier: code_verifier.to_s }.merge(TokenService.client_authentication(url))
      response = Faraday.post(url, URI.encode_www_form(form), "Content-Type" => "application/x-www-form-urlencoded")
      body = JSON.parse(response.body.to_s)
      raise Refused, "Microsoft did not complete the sign-in: #{body['error_description'].to_s.lines.first}" unless body["id_token"]

      claims = JWT.decode(body["id_token"], nil, false).first
      raise Refused, "The sign-in was issued to another application" unless claims["aud"] == Config.app_id
      raise Refused, "The sign-in has expired" if claims["exp"].to_i < Time.current.to_i

      claims
    rescue JSON::ParserError
      raise Refused, "Microsoft answered the sign-in with something other than JSON"
    end
  end
end
