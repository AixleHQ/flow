# frozen_string_literal: true

module Auth
  module Methods
    # Enterprise SAML, reached only through the sidecar (AD-8).
    #
    # This process never sees XML. The customer's IdP posts its assertion to the
    # bridge; the bridge hands us an ordinary OAuth code, which we exchange for a
    # profile. `ruby-saml` is deliberately absent from this application — five
    # Critical authentication-bypass advisories in fifteen months is not a
    # dependency to carry in the process that serves the app.
    #
    # The connection row stores the bridge's tenant/product keys, not IdP
    # metadata: the metadata lives in the bridge, which is the thing that parses
    # it.
    class Saml < Auth::Method
      def authorize_url(redirect_uri:, state:, **)
        params = {
          response_type: "code",
          # The bridge identifies a connection by tenant+product carried in the
          # client_id, which is its documented shape.
          client_id: "tenant=#{tenant}&product=#{product}",
          redirect_uri: redirect_uri,
          state: state
        }
        uri = URI.parse("#{bridge_url}/api/oauth/authorize")
        uri.query = params.to_query
        uri.to_s
      end

      def complete(code:, redirect_uri:, **)
        token = exchange_code(code: code, redirect_uri: redirect_uri)
        profile = fetch_profile(token)
        verify_connection!(profile)

        Auth::Assertion.new(
          provider: provider,
          # The bridge's stable per-user id, derived from the assertion's NameID.
          subject: profile.fetch("id").to_s,
          email: profile["email"],
          # A SAML assertion comes from the customer's own directory, which owns
          # the addresses in it — the same reasoning as an Entra work account.
          email_verified: true,
          name: [ profile["firstName"], profile["lastName"] ].compact_blank.join(" ").presence
        )
      end

      private

      def bridge_url = Settings.sso_bridge&.url.to_s.chomp("/")
      def tenant = provider.config["tenant"].presence || "company-#{provider.company_id}"
      def product = provider.config["product"].presence || Settings.project_name.to_s.downcase

      def exchange_code(code:, redirect_uri:)
        response = Faraday.post("#{bridge_url}/api/oauth/token") do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = {
            grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
            client_id: "tenant=#{tenant}&product=#{product}",
            client_secret: Settings.sso_bridge&.client_secret
          }.to_query
        end
        raise Auth::Method::Failure, "bridge token endpoint returned #{response.status}" unless response.success?

        JSON.parse(response.body).fetch("access_token")
      rescue JSON::ParserError, KeyError
        raise Auth::Method::Failure, "bridge token endpoint returned an unusable body"
      end

      def fetch_profile(token)
        response = Faraday.get("#{bridge_url}/api/oauth/userinfo") do |req|
          req.headers["Authorization"] = "Bearer #{token}"
        end
        raise Auth::Method::Failure, "bridge userinfo returned #{response.status}" unless response.success?

        JSON.parse(response.body)
      rescue JSON::ParserError
        raise Auth::Method::Failure, "bridge userinfo returned a non-JSON body"
      end

      # AD-13: one bridge serves every customer, so the profile must name the
      # connection it claims to satisfy. Without this a code minted for one
      # tenant would be accepted for another — the confused deputy the whole
      # binding rule exists to stop.
      def verify_connection!(profile)
        requested = profile["requested"] || {}
        return if requested["tenant"].to_s == tenant && requested["product"].to_s == product

        raise Auth::Method::Failure,
              "bridge profile for tenant #{requested['tenant'].inspect} does not match this connection"
      end
    end
  end
end
