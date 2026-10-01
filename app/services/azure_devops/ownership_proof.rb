# frozen_string_literal: true

module AzureDevops
  # Proof that the person connecting an Azure DevOps organization actually
  # controls it.
  #
  # This is the check the whole binding model exists for, and the reason it
  # cannot be "does our application have access to that organization": with a
  # multi-tenant application installed by several customers, the answer is
  # legitimately yes for every one of them. A project administrator in company A
  # naming company B's organization would get a working connection into it.
  #
  # Knowing the name is not proof either — organization names are short, guessable
  # and usually public.
  #
  # So the requester proves it, once: by signing in with Microsoft, or with a
  # personal access token (AdminCredential). Either is used to call an endpoint
  # only an organization administrator can call, and is then discarded: it is
  # never written to the database, never logged, and never outlives the
  # onboarding. What survives is the binding it justified.
  #
  # A PAT needs **Member Entitlement Management (read & write)** — the same
  # permission family as adding a user to the organization, which is exactly the
  # authority being claimed — and **Security (manage)**, which onboarding spends
  # on one grant so the application can manage its own Service Hooks afterwards
  # (see AzureDevops::ServiceHookGrant). Only the first is checked here: the
  # second buys events rather than access, and a connection without it works.
  class OwnershipProof
    # Member Entitlement Management lives on its own host, not dev.azure.com.
    HOST = "https://vsaex.dev.azure.com"
    API_VERSION = "7.1-preview.1"

    Result = Struct.new(:organization, :identity, :verified_at, keyword_init: true)

    def self.call(organization:, admin:)
      new(organization: organization, admin: admin).call
    end

    def initialize(organization:, admin:, logger: Rails.logger)
      @organization = organization.to_s.strip
      @admin = admin
      @logger = logger
    end

    # Raises unless the token can administer the organization. Returns who it
    # belongs to, for the audit trail on the binding.
    def call
      raise ValidationFailed, "Sign in with Microsoft or give a personal access token" if @admin.nil?

      response = get("_apis/userentitlements", "$top" => 1)

      # Azure DevOps answers an invalid credential with a 302 to an HTML sign-in
      # page rather than a 401 — a browser-shaped reply to an API call. So the
      # rule is "did we get JSON": anything else means we were not
      # authenticated, whatever the status line says.
      if signed_out?(response)
        raise NotAuthorized, not_valid_message
      end

      case response.status
      when 200 then Result.new(organization: @organization, identity: identity_of(response), verified_at: Time.current)
      when 401
        raise NotAuthorized, not_valid_message
      when 403
        # Authenticated and refused: a real token from someone who is not an
        # administrator. Distinct from 401 on purpose — the message tells them
        # which of the two to fix.
        raise NotAuthorized, not_admin_message
      when 404
        raise NotFound, "No Azure DevOps organization named '#{@organization}'"
      else
        raise Error.new("Azure answered #{response.status} while verifying the organization",
                        code: "ownership_check_failed", status: response.status)
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Error.new("Could not reach Azure DevOps (#{e.class})", code: "azure_unreachable")
    end

    # The projects this administrator can see, listed with THEIR token rather
    # than the application's — at this point the application is not in the
    # organization yet and its own token is refused outright, so this is the
    # only credential that can produce the list.
    #
    # A failure here is NOT an empty list. It used to be: any non-200 returned
    # `[]`, so a token missing the project scope produced a cheerful "verified"
    # and an empty dropdown with nothing to pick and nothing to explain. The
    # scopes are not guessable from the outside, so the error has to name the
    # one that is missing.
    def projects(limit: 200)
      response = Faraday.new(url: AppConfig.api_host) { |f| transport(f) }
                        .get("/#{ERB::Util.url_encode(@organization)}/_apis/projects") do |req|
        req.headers["Authorization"] = authorization
        req.params["api-version"] = Client::API_VERSIONS[:core]
        req.params["$top"] = limit
      end

      if signed_out?(response) || [ 401, 403 ].include?(response.status)
        raise NotAuthorized, cannot_list_message
      end
      unless response.status == 200
        raise Error.new("Azure answered #{response.status} while listing the organization's projects",
                        code: "project_listing_failed", status: response.status)
      end

      Array(JSON.parse(response.body)["value"]).map do |project|
        { id: project["id"], name: project["name"], description: project["description"],
          visibility: project["visibility"] }.compact
      end
    rescue JSON::ParserError
      raise Error.new("Azure's project list could not be read", code: "project_listing_failed")
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Error.new("Could not reach Azure DevOps (#{e.class})", code: "azure_unreachable")
    end

    private

    # A redirect, or a non-JSON body, is Azure bouncing us to a login page.
    def signed_out?(response)
      return true if (300..399).cover?(response.status)

      response.headers["content-type"].to_s.include?("text/html")
    end

    def get(path, params = {})
      Faraday.new(url: HOST) { |f| transport(f) }
             .get("/#{ERB::Util.url_encode(@organization)}/#{path}") do |req|
        req.headers["Authorization"] = authorization
        req.params["api-version"] = API_VERSION
        req.params.update(params)
      end
    end

    def authorization = @admin.authorization

    def not_valid_message
      return "Your Microsoft sign-in is not accepted by '#{@organization}'. Sign in again with an account in its directory." if @admin.sign_in?

      "That personal access token is not valid for organization '#{@organization}'. " \
        "Check it has not expired and was created in this organization."
    end

    def not_admin_message
      if @admin.sign_in?
        return "You are signed in, but your account cannot administer '#{@organization}'. " \
               "Connecting an organization has to be done by someone who can add users to it."
      end

      "That token works, but it cannot administer '#{@organization}'. " \
        "Connecting an organization has to be done by someone who can add users to it, " \
        "with a token carrying Member Entitlement Management (read & write)."
    end

    def cannot_list_message
      return "You administer '#{@organization}', but your account cannot list its projects." if @admin.sign_in?

      "That token proved you administer '#{@organization}', but it cannot list its projects. " \
        "Add the Project and team (read) scope to it — Azure does not include project access " \
        "in the Member Entitlement Management scope."
    end

    # A sign-in names the person itself; for a PAT the entitlement listing is all there is.
    def identity_of(response)
      return @admin.identity if @admin.sign_in?

      body = JSON.parse(response.body)
      # Best effort: the binding records who vouched, and a missing display name
      # must not fail a verification that otherwise succeeded.
      Array(body["members"]).first&.dig("user", "principalName")
    rescue JSON::ParserError
      nil
    end

    def transport(faraday)
      faraday.options.open_timeout = AppConfig.open_timeout
      faraday.options.timeout = AppConfig.read_timeout
      faraday.adapter Faraday.default_adapter
    end
  end
end
