# frozen_string_literal: true

module Gitlab
  # The deployment's GitLab OAuth app (docs/design/gitlab-tracker.md §4). It is
  # used once per connection: a group Owner consents, and with that token Flow
  # creates the service account the connection then runs as.
  module Oauth
    PROVIDER = "gitlab"
    SCOPES = %w[api].freeze

    module_function

    def authorize_url(project:, user:)
      verifier = SecureRandom.urlsafe_base64(64)
      state = ::Oauth::State.encode(owner_type: "Project", owner_id: project.id, user_id: user.id, return_to: nil,
                                    code_verifier: verifier, provider: PROVIDER)
      query = URI.encode_www_form(
        client_id: AppConfig.oauth_client_id, redirect_uri: redirect_uri, response_type: "code", scope: SCOPES.join(" "),
        state: state, code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
        code_challenge_method: "S256"
      )
      "#{Host.web_base}/oauth/authorize?#{query}"
    end

    def redirect_uri
      "#{Settings.protocol}://#{Settings.domain}/integrations/gitlab/oauth/callback"
    end

    # { "access_token", "refresh_token", "expires_at" }.
    def exchange_code(code, code_verifier:)
      response = http.post("/oauth/token", URI.encode_www_form(
        grant_type: "authorization_code", code: code.to_s, redirect_uri: redirect_uri, code_verifier: code_verifier.to_s,
        client_id: AppConfig.oauth_client_id, client_secret: AppConfig.oauth_client_secret
      ), "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json")
      data = response.body.present? ? JSON.parse(response.body) : {}
      unless response.success?
        message = data["error_description"].presence || data["error"].presence || "status #{response.status}"
        code = (400..403).cover?(response.status) ? "not_authorized" : "provider_error"
        raise Trackers::Error.new("GitLab refused the authorization: #{message.to_s.truncate(200)}", code: code)
      end

      {
        "access_token" => data["access_token"], "refresh_token" => data["refresh_token"],
        "expires_at" => data["expires_in"].present? ? (Time.current + data["expires_in"].to_i.seconds).iso8601 : nil
      }.compact
    rescue Faraday::Error, JSON::ParserError => e
      raise Trackers::Error.new("GitLab's token endpoint did not answer (#{e.class})", code: "provider_error")
    end

    def http
      Faraday.new(url: Host.web_base) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        f.adapter Faraday.default_adapter
      end
    end
  end
end
