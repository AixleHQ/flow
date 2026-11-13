# frozen_string_literal: true

module Gitlab
  # The GitLab calls made with a person's own OAuth token
  # (docs/design/gitlab-user-identity.md §4.1). The host is the deployment's
  # (GITLAB_ENDPOINT), never one a request names. The token is only ever sent to
  # GitLab from here, and no message carries it or a response body.
  class UserTokenService
    class Error < StandardError; end
    # GitLab no longer accepts the user's token (revoked, expired or never valid).
    class InvalidToken < Error; end
    # GitLab refused the request.
    class Forbidden < Error; end
    # GitLab answered with a server error or not at all, which says nothing about the token.
    class Unavailable < Error; end

    # Access levels GitLab reports (Developer may push to unprotected branches).
    DEVELOPER = 30

    # @return [Hash] { id:, username:, name:, avatar_url:, commit_email: }
    def user(token)
      data = translating { rest(token).get("/user") }
      raise Unavailable, "GitLab returned no user" unless data.is_a?(Hash) && data["id"].present?

      { id: data["id"], username: data["username"], name: data["name"], avatar_url: data["avatar_url"],
        commit_email: data["commit_email"].presence }
    end

    # The person's effective access level on a project, or nil when the project is not
    # visible to them. `permissions` on the project answers for direct and parent-group
    # membership; a project reached only through a group it is shared with is not always
    # reported there, so a lower answer is checked against the project's member list,
    # which counts inherited and invited members too.
    # @return [Integer, nil]
    def project_access(token, full_path, user_id: nil)
      project = ERB::Util.url_encode(full_path.to_s)
      data = translating(not_found: nil) { rest(token).get("/projects/#{project}") }
      return nil unless data.is_a?(Hash)

      permissions = data["permissions"].to_h
      level = %w[project_access group_access].filter_map { |key| permissions.dig(key, "access_level") }.max
      return level if level.to_i >= DEVELOPER || user_id.blank?

      [ level.to_i, member_access(token, data["id"], user_id).to_i ].max.nonzero?
    end

    # Ends the grant. Callers treat a failure as non-fatal.
    def revoke(token)
      uri = URI.parse("#{Host.web_base}/oauth/revoke")
      http = SafeHttp.http_for(uri, open_timeout: AppConfig.open_timeout, read_timeout: AppConfig.read_timeout,
                                    trusted_hosts: [ uri.host ])
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(client_id: AppConfig.oauth_client_id, client_secret: AppConfig.oauth_client_secret,
                        token: token)
      response = http.request(req)
      raise Unavailable, "GitLab did not revoke the grant (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

      true
    rescue SafeHttp::UnsafeUrl, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Unavailable, "GitLab is unavailable (#{e.class.name})"
    end

    private

    def rest(token) = Rest.new(token: token)

    def member_access(token, project_id, user_id)
      data = translating(not_found: nil) { rest(token).get("/projects/#{project_id.to_i}/members/all/#{user_id.to_i}") }
      data.is_a?(Hash) ? data["access_level"] : nil
    rescue Forbidden
      nil
    end

    def translating(not_found: :forbidden)
      yield
    rescue Trackers::Error => e
      case e.code
      when "not_authorized" then raise InvalidToken, "GitLab does not accept this user token"
      when "not_found" then not_found == :forbidden ? raise(Forbidden, "GitLab refused the request") : not_found
      when "permission_denied", "validation_failed" then raise Forbidden, "GitLab refused the request"
      else raise Unavailable, "GitLab is unavailable"
      end
    end
  end
end
