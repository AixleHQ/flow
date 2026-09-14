# frozen_string_literal: true

module AzureDevops
  # Which Microsoft Entra tenant backs an Azure DevOps organization.
  #
  # Asked rather than typed. The tenant id is a GUID nobody knows by heart, and
  # making someone paste one is both a support burden and a chance to paste the
  # wrong one — which would produce a token for a directory that has nothing to
  # do with the organization being connected.
  #
  # Azure answers it for free: an unauthenticated request to any organization
  # endpoint comes back with a `WWW-Authenticate: Bearer authorization_uri=...`
  # header naming the tenant. That is standard Entra resource behaviour, not a
  # trick, and it is what every Microsoft client library uses to discover an
  # authority.
  class TenantDiscovery
    AUTHORIZATION_URI = %r{authorization_uri=(?<uri>https://\S+?)(?:[,\s]|\z)}
    GUID = /\A[0-9a-fA-F-]{36}\z/

    Result = Struct.new(:tenant_id, :organization, keyword_init: true)

    # An organization backed by a personal Microsoft account has no tenant at
    # all, and answers without the header — that is the MSA case, and it is a
    # different message to the user than "we could not reach Azure".
    class NoTenant < Error
      def initialize(message = nil)
        super(message, code: "organization_has_no_tenant")
      end
    end

    def self.call(organization)
      new(organization).call
    end

    def initialize(organization, logger: Rails.logger)
      @organization = organization.to_s.strip
      @logger = logger
    end

    def call
      unless @organization.match?(AzureDevopsInstallation::ORGANIZATION_SLUG)
        raise ValidationFailed, "'#{@organization}' is not a valid Azure DevOps organization name"
      end

      # An ORGANIZATION-level git endpoint, deliberately: every other call this
      # adapter makes is project-scoped, so nothing else can be confused with
      # this one. `_apis/connectionData` would be the obvious choice and is not
      # usable — it answers 200 without credentials and therefore never sends
      # the header we are here for.
      response = connection.get("/#{ERB::Util.url_encode(@organization)}/_apis/git/repositories") do |req|
        req.params["api-version"] = Client::API_VERSIONS[:git]
      end

      # Unauthenticated, Azure answers 302 to a sign-in page and names the
      # tenant in the header on the way. A 404 means the organization is not
      # there at all.
      raise NotFound, "No Azure DevOps organization named '#{@organization}'" if response.status == 404

      tenant = tenant_from(response)
      raise NoTenant, msa_message if tenant.blank?

      Result.new(tenant_id: tenant, organization: @organization)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Error.new("Could not reach Azure DevOps (#{e.class})", code: "azure_unreachable")
    end

    private

    def tenant_from(response)
      header = Array(response.headers["www-authenticate"]).join(", ")
      match = header.match(AUTHORIZATION_URI)
      return nil if match.nil?

      candidate = URI.parse(match[:uri]).path.to_s.split("/").reject(&:blank?).last
      candidate if candidate.to_s.match?(GUID)
    rescue URI::InvalidURIError
      nil
    end

    def msa_message
      "Organization '#{@organization}' is not backed by a Microsoft Entra directory. " \
        "Organizations on a personal Microsoft account cannot use a service principal at all — " \
        "connect it with a personal access token instead."
    end

    def connection
      @connection ||= Faraday.new(url: AppConfig.api_host) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        f.adapter Faraday.default_adapter
      end
    end
  end
end
