# frozen_string_literal: true

module SsoBridge
  # App-owned adapter for the SAML bridge's admin API (AD-8, AD-9).
  #
  # The bridge is the only thing in this system that parses SAML. Wrapping it
  # here means the rest of the app never learns its wire format, and the boundary
  # has one fake and one contract test instead of stubs scattered through feature
  # tests.
  #
  # The admin API is reached at `admin_url`, which is cluster-internal: only the
  # bridge's ACS endpoint is publicly routable, because a customer's IdP has to
  # POST assertions to it.
  class Client
    class Error < StandardError; end
    class NotConfigured < Error; end

    def self.configured?
      Settings.sso_bridge&.url.present? && Settings.sso_bridge&.api_key.present?
    end

    def initialize(admin_url: nil, api_key: nil)
      @admin_url = (admin_url || Settings.sso_bridge&.admin_url).to_s.chomp("/")
      @api_key = api_key || Settings.sso_bridge&.api_key
      raise NotConfigured, "no SAML bridge configured" if @admin_url.blank? || @api_key.blank?
    end

    # Registers (or replaces) one customer's SAML connection.
    def upsert_connection(tenant:, product:, redirect_url:, default_redirect_url:, name:,
                          metadata_url: nil, raw_metadata: nil)
      if metadata_url.blank? && raw_metadata.blank?
        raise Error, "a SAML connection needs either metadata_url or raw_metadata"
      end

      body = {
        tenant: tenant, product: product, name: name,
        defaultRedirectUrl: default_redirect_url,
        # The bridge validates the post-login redirect against this allowlist, so
        # it is a security control, not a convenience.
        redirectUrl: [ redirect_url ].to_json
      }
      body[:metadataUrl] = metadata_url if metadata_url.present?
      body[:encodedRawMetadata] = Base64.strict_encode64(raw_metadata) if raw_metadata.present?

      post_form("/api/v1/sso", body)
    end

    def delete_connection(tenant:, product:)
      response = Faraday.delete("#{admin_url}/api/v1/sso") do |req|
        req.headers["Authorization"] = "Api-Key #{api_key}"
        req.params.update(tenant: tenant, product: product)
      end
      raise Error, "bridge returned #{response.status}" unless response.success?

      true
    end

    private

    attr_reader :admin_url, :api_key

    def post_form(path, body)
      response = Faraday.post("#{admin_url}#{path}") do |req|
        req.headers["Authorization"] = "Api-Key #{api_key}"
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = body.to_query
      end
      parse!(response)
    end

    def parse!(response)
      raise Error, "bridge returned #{response.status}: #{response.body.to_s.first(200)}" unless response.success?

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise Error, "bridge returned a non-JSON body"
    end
  end
end
