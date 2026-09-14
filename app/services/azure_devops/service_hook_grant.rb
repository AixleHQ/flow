# frozen_string_literal: true

module AzureDevops
  # Lets the application manage its own Service Hook subscriptions.
  #
  # Creating a subscription needs the *View subscriptions* and *Edit
  # subscriptions* permissions, which Azure gives only to project administrators
  # by default. The application is entitled as a project Contributor, so without
  # this it can never create one — CI gates still resolve, but only through the
  # five-minute recovery sweep, and the event path is dead.
  #
  # The alternative was to create the subscriptions with the administrator's own
  # personal access token during onboarding. That works, and it makes the
  # subscription belong to that person: Azure does not trigger a subscription
  # whose creator has lost access to the resource, so the day they leave the
  # company the events stop and nothing says so. The whole point of running on a
  # service principal is that an employee leaving changes nothing, and a webhook
  # that quietly stops is worse than one that was never created.
  #
  # So the token is spent on a GRANT rather than on a subscription. One ACE, set
  # once, and afterwards the application creates and re-creates its own hooks —
  # at connect time, and on every later "Test connection".
  #
  # The permission is narrow: these two bits are only about service hook
  # subscriptions in one project, and carry no access to code, work items or
  # settings.
  class ServiceHookGrant
    NAMESPACE_ID = "cb594ebe-87dd-4fc9-ac2c-6a10a4c92046"
    API_VERSION = "7.1-preview.1"
    IDENTITY_HOST = "https://vssps.dev.azure.com"

    # From the namespace itself (`_apis/securitynamespaces/<id>`), not from
    # memory: ViewSubscriptions = 1, EditSubscriptions = 2. DeleteSubscriptions
    # (4) is deliberately not granted — Azure's own reference says Edit can
    # already delete a subscription, so the extra bit buys nothing.
    VIEW_SUBSCRIPTIONS = 1
    EDIT_SUBSCRIPTIONS = 2
    ALLOW = VIEW_SUBSCRIPTIONS | EDIT_SUBSCRIPTIONS

    # The ServiceHooks namespace is documented as internal and Microsoft
    # publishes no token format for it. This is the shape the product uses for
    # project-scoped subscription permissions, and the namespace descriptor
    # agrees with it: a hierarchical namespace with "/" as its separator and
    # variable-length parts.
    #
    # Because it is not documented, it is not trusted either — `Onboarding`
    # proves the grant by having the application actually create a subscription
    # afterwards, so a wrong token shape shows up as a failure to provision
    # rather than as an ACE that quietly grants nothing.
    def self.token_for(project_id) = "PublisherSecurity/#{project_id}"

    def initialize(organization:, personal_access_token:, tenant_id:, principal_object_id:,
                   logger: Rails.logger)
      @organization = organization.to_s.strip
      @pat = personal_access_token.to_s
      @tenant_id = tenant_id.to_s
      @principal_object_id = principal_object_id.to_s
      @logger = logger
    end

    # Grants the two permissions on each project. Returns the descriptor it
    # granted to, so a caller can log what it did.
    def call(project_ids)
      raise ValidationFailed, "A personal access token is required" if @pat.blank?
      raise ValidationFailed, "The application has no service principal id yet" if @principal_object_id.blank?

      descriptor = identity_descriptor

      Array(project_ids).each do |project_id|
        set_ace(token: self.class.token_for(project_id), descriptor: descriptor)
      end

      descriptor
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Error.new("Could not reach Azure DevOps (#{e.class})", code: "azure_unreachable")
    end

    private

    # What Azure calls this identity in an ACE. Asked rather than assembled: the
    # descriptor is Azure's name for the identity, and an identity that has just
    # been entitled is the one case where it is worth hearing Azure say it.
    #
    # The fallback is the exact shape Azure returns for an AAD service principal
    # and is used only when the lookup answers nothing — which would otherwise
    # turn a momentary identity-propagation delay into a permanent missing
    # grant.
    def identity_descriptor
      response = Faraday.new(url: IDENTITY_HOST) { |f| transport(f) }
                        .get("/#{ERB::Util.url_encode(@organization)}/_apis/identities") do |req|
        req.headers["Authorization"] = authorization
        req.params["searchFilter"] = "General"
        req.params["filterValue"] = @principal_object_id
        req.params["queryMembership"] = "None"
        req.params["api-version"] = API_VERSION
      end

      found = parse(response)&.dig("value")&.first&.dig("descriptor")
      return found if found.present?

      @logger.info("[AzureDevops::ServiceHookGrant] no identity row for #{@principal_object_id} yet; " \
                   "using the standard service principal descriptor")
      "Microsoft.VisualStudio.Services.Claims.AadServicePrincipal;#{@tenant_id}\\#{@principal_object_id}"
    end

    # `merge: true` so an organization that has already set its own service hook
    # permissions keeps them — this adds two bits, it does not replace an ACL.
    def set_ace(token:, descriptor:)
      response = Faraday.new(url: AppConfig.api_host) { |f| transport(f) }
                        .post("/#{ERB::Util.url_encode(@organization)}/_apis/accesscontrolentries/#{NAMESPACE_ID}") do |req|
        req.headers["Authorization"] = authorization
        req.headers["Content-Type"] = "application/json"
        req.params["api-version"] = API_VERSION
        req.body = {
          token: token, merge: true,
          accessControlEntries: [ { descriptor: descriptor, allow: ALLOW, deny: 0 } ]
        }.to_json
      end

      return if response.status == 200

      # Same browser-shaped refusal as everywhere else in onboarding: Azure
      # answers a bad credential with a redirect to a sign-in page.
      if (300..399).cover?(response.status) || html?(response)
        raise NotAuthorized, "That personal access token is not valid for '#{@organization}'"
      end
      if [ 401, 403 ].include?(response.status)
        raise NotAuthorized,
              "That token cannot manage permissions in '#{@organization}'. Granting Aixle permission to " \
              "manage its own Service Hooks needs a token with the Security (manage) scope."
      end

      raise Error.new("Azure refused the Service Hooks permission grant (#{response.status})",
                      code: "service_hook_grant_failed", status: response.status)
    end

    def parse(response)
      return nil unless response.status == 200 && !html?(response)

      JSON.parse(response.body)
    rescue JSON::ParserError
      nil
    end

    def html?(response) = response.headers["content-type"].to_s.include?("text/html")

    def authorization = "Basic #{Base64.strict_encode64(":#{@pat}")}"

    def transport(faraday)
      faraday.options.open_timeout = AppConfig.open_timeout
      faraday.options.timeout = AppConfig.read_timeout
      faraday.adapter Faraday.default_adapter
    end
  end
end
