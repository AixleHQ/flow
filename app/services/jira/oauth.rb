# frozen_string_literal: true

module Jira
  # Atlassian's token endpoints — the 3LO authorization-code flow of the
  # deployment's app and the client-credentials grant of a customer's service
  # account — and the two lookups that turn either into a site's cloud id.
  module Oauth
    PROVIDER = "jira"
    # Board configuration is in the Jira Software API, which has only granular
    # scopes; the classic ones cover the platform API.
    SCOPES = %w[
      read:jira-work write:jira-work read:jira-user manage:jira-webhook
      read:board-scope:jira-software read:board-scope.admin:jira-software read:project:jira
      offline_access
    ].freeze
    SITE_HOST = /\A[a-z0-9][a-z0-9-]*\.(?:atlassian\.net|jira\.com)\z/

    module_function

    def authorize_url(project:, user:)
      state = ::Oauth::State.encode(owner_type: "Project", owner_id: project.id, user_id: user.id, return_to: nil,
                                    code_verifier: nil, provider: PROVIDER)
      query = URI.encode_www_form(
        audience: "api.atlassian.com", client_id: AppConfig.client_id, scope: SCOPES.join(" "),
        redirect_uri: redirect_uri, state: state, response_type: "code", prompt: "consent"
      )
      "#{AppConfig::AUTH_HOST}/authorize?#{query}"
    end

    def redirect_uri
      "#{Settings.protocol}://#{Settings.domain}/integrations/jira/oauth/callback"
    end

    def exchange_code(code)
      token_request(grant_type: "authorization_code", client_id: AppConfig.client_id,
                    client_secret: AppConfig.client_secret, code: code.to_s, redirect_uri: redirect_uri)
    end

    def refresh(refresh_token)
      raise Error.new("This connection holds no refresh token", code: "not_authorized") if refresh_token.blank?

      token_request(grant_type: "refresh_token", client_id: AppConfig.client_id,
                    client_secret: AppConfig.client_secret, refresh_token: refresh_token)
    end

    def client_credentials(client_id:, client_secret:)
      token_request(grant_type: "client_credentials", client_id: client_id.to_s, client_secret: client_secret.to_s)
    end

    # The Jira sites a 3LO token was granted: [{ id: cloud id, name:, url: }].
    def accessible_resources(access_token)
      response = http(AppConfig::API_HOST).get("/oauth/token/accessible-resources", nil,
                                               "Authorization" => "Bearer #{access_token}", "Accept" => "application/json")
      unless response.success?
        raise Error.new("Atlassian did not list the granted sites (#{response.status})",
                        code: response.status == 401 ? "not_authorized" : "provider_error", status: response.status)
      end

      Array(JSON.parse(response.body)).filter_map do |resource|
        next unless Array(resource["scopes"]).any? { |scope| scope.include?("jira") }

        { id: resource["id"].to_s, name: resource["name"].to_s, url: resource["url"].to_s }
      end.uniq { |site| site[:id] }
    rescue Faraday::Error, JSON::ParserError => e
      raise Error.new("Atlassian did not list the granted sites (#{e.class})", code: "provider_error")
    end

    # A site's cloud id, from its public tenant endpoint. Only Atlassian's own
    # site domains are fetched, whatever was typed.
    def cloud_id_for(site_url)
      host = site_host!(site_url)
      response = http("https://#{host}").get("/_edge/tenant_info", nil, "Accept" => "application/json")
      cloud_id = response.success? ? JSON.parse(response.body)["cloudId"].to_s.presence : nil
      raise Error.new("#{host} is not a Jira Cloud site", code: "not_found", status: response.status) unless cloud_id

      cloud_id
    rescue Faraday::Error, JSON::ParserError => e
      raise Error.new("Could not reach #{host} (#{e.class})", code: "provider_error")
    end

    def site_host!(site_url)
      value = site_url.to_s.strip
      value = "https://#{value}" unless value.match?(%r{\Ahttps?://}i)
      host = URI.parse(value).host.to_s.downcase
      return host if host.match?(SITE_HOST)

      raise Error.new("Enter the Jira Cloud site, like your-team.atlassian.net", code: "validation_failed")
    rescue URI::InvalidURIError
      raise Error.new("Enter the Jira Cloud site, like your-team.atlassian.net", code: "validation_failed")
    end

    # { "access_token", "refresh_token", "expires_at" }. Atlassian rotates the
    # refresh token on every refresh, so the caller must store the new one.
    def token_request(**body)
      response = http(AppConfig::AUTH_HOST).post("/oauth/token", body.to_json,
                                                 "Content-Type" => "application/json", "Accept" => "application/json")
      data = response.body.present? ? JSON.parse(response.body) : {}
      unless response.success?
        message = data["error_description"].presence || data["error"].presence || "status #{response.status}"
        code = (400..403).cover?(response.status) ? "not_authorized" : "provider_error"
        raise Error.new("Atlassian refused the credential: #{message.to_s.truncate(200)}", code: code, status: response.status)
      end

      {
        "access_token" => data["access_token"], "refresh_token" => data["refresh_token"],
        "expires_at" => (Time.current + data["expires_in"].to_i.seconds).iso8601
      }.compact
    rescue Faraday::Error, JSON::ParserError => e
      raise Error.new("Atlassian's token endpoint did not answer (#{e.class})", code: "provider_error")
    end

    def http(host)
      Faraday.new(url: host) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        f.adapter Faraday.default_adapter
      end
    end
  end
end
