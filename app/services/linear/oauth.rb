# frozen_string_literal: true

module Linear
  # The deployment's Linear OAuth app. It is installed with actor=app, so it
  # writes as itself rather than as the person who installed it, and only a
  # workspace admin can install it.
  module Oauth
    PROVIDER = "linear"
    SCOPES = %w[read write].freeze

    module_function

    def authorize_url(project:, user:)
      state = ::Oauth::State.encode(owner_type: "Project", owner_id: project.id, user_id: user.id, return_to: nil,
                                    code_verifier: nil, provider: PROVIDER)
      query = URI.encode_www_form(
        client_id: AppConfig.client_id, redirect_uri: redirect_uri, response_type: "code", scope: SCOPES.join(","),
        state: state, actor: "app", prompt: "consent"
      )
      "#{AppConfig::AUTHORIZE_URL}?#{query}"
    end

    def redirect_uri
      "#{Settings.protocol}://#{Settings.domain}/integrations/linear/oauth/callback"
    end

    def exchange_code(code)
      token_request(grant_type: "authorization_code", code: code.to_s, redirect_uri: redirect_uri,
                    client_id: AppConfig.client_id, client_secret: AppConfig.client_secret)
    end

    def refresh(refresh_token)
      raise Trackers::Error.new("This connection holds no refresh token", code: "not_authorized") if refresh_token.blank?

      token_request(grant_type: "refresh_token", refresh_token: refresh_token,
                    client_id: AppConfig.client_id, client_secret: AppConfig.client_secret)
    end

    # { "access_token", "refresh_token", "expires_at" }. Linear rotates the
    # refresh token on every refresh, so the caller must store the new one.
    def token_request(**form)
      response = http.post("/oauth/token", URI.encode_www_form(form),
                           "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json")
      data = response.body.present? ? JSON.parse(response.body) : {}
      unless response.success?
        message = data["error_description"].presence || data["error"].presence || "status #{response.status}"
        code = (400..403).cover?(response.status) ? "not_authorized" : "provider_error"
        raise Trackers::Error.new("Linear refused the authorization: #{message.to_s.truncate(200)}", code: code)
      end

      {
        "access_token" => data["access_token"], "refresh_token" => data["refresh_token"],
        "expires_at" => data["expires_in"].present? ? (Time.current + data["expires_in"].to_i.seconds).iso8601 : nil
      }.compact
    rescue Faraday::Error, JSON::ParserError => e
      raise Trackers::Error.new("Linear's token endpoint did not answer (#{e.class})", code: "provider_error")
    end

    def http
      Faraday.new(url: AppConfig::API_HOST) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        f.adapter Faraday.default_adapter
      end
    end
  end
end
