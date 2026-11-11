# frozen_string_literal: true

module Github
  # The GitHub calls made on a user's behalf, with the GitHub App's own client
  # credentials (docs/design/github-user-identity.md §4.4). The user's stored
  # token is only ever sent to GitHub from here; callers get scoped tokens back.
  class UserTokenService
    class Error < StandardError; end
    # GitHub no longer accepts the user's token (revoked, expired or never valid).
    class InvalidToken < Error; end
    # GitHub refused the request: no access to the owner or the repositories.
    class Forbidden < Error; end
    # GitHub answered with a server error, which says nothing about the token.
    class Unavailable < Error; end

    # Mints a token limited to `repositories` of one owner and `permissions`. The
    # result can never exceed what the App, the installation and the user share.
    # @return [Hash] { token:, expires_at:, token_last_eight: }
    def scoped_token(user_token:, target:, repositories:, permissions:)
      body = { access_token: user_token, target: target, repositories: repositories, permissions: permissions }
      response = translating { app_client.post("applications/#{client_id}/token/scoped", body) }
      token = response[:token].to_s
      raise Unavailable, "GitHub returned no token" if token.blank?

      { token: token, expires_at: parse_time(response[:expires_at]), token_last_eight: response[:token_last_eight] }
    end

    # @return [Hash] { id:, login:, name:, avatar_url: }
    def user(user_token)
      data = translating { Octokit::Client.new(access_token: user_token).user }
      { id: data[:id], login: data[:login], name: data[:name], avatar_url: data[:avatar_url] }
    end

    # Ends the user's grant of the App. Callers treat a failure as non-fatal.
    def revoke_grant(user_token)
      translating { app_client.delete("applications/#{client_id}/grant", access_token: user_token) }
      true
    end

    private

    def client_id = Settings.github.client_id

    def app_client
      @app_client ||= Octokit::Client.new(login: client_id, password: Settings.github.client_secret)
    end

    def translating
      yield
    rescue Octokit::NotFound, Octokit::Unauthorized
      raise InvalidToken, "GitHub does not accept this user token"
    rescue Octokit::Forbidden, Octokit::UnprocessableEntity => e
      raise Forbidden, "GitHub refused the request (#{e.response_status})"
    rescue Octokit::ServerError, Faraday::Error => e
      raise Unavailable, "GitHub is unavailable (#{e.class.name})"
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    end
  end
end
