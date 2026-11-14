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
      data = translating { client(token).user }.to_h
      raise Unavailable, "GitLab returned no user" if data["id"].blank?

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
      project = translating(not_found: nil) { client(token).project(full_path.to_s) }
      return nil if project.nil?

      project = project.to_h
      permissions = project["permissions"].to_h
      level = %w[project_access group_access].filter_map { |key| permissions.dig(key, "access_level") }.max
      return level if level.to_i >= DEVELOPER || user_id.blank?

      [ level.to_i, member_access(token, project["id"], user_id).to_i ].max.nonzero?
    end

    private

    # The gem sends `Authorization: Bearer` for a token of 64 characters or more, which
    # a GitLab OAuth token is (a shorter one would go as `PRIVATE-TOKEN`).
    def client(token)
      ::Gitlab.client(endpoint: Host.api_endpoint, private_token: token,
                      httparty: { open_timeout: AppConfig.open_timeout, read_timeout: AppConfig.read_timeout })
    end

    def member_access(token, project_id, user_id)
      members = translating(not_found: nil) { client(token).all_members(project_id, user_ids: [ user_id.to_i ]) }
      members.to_a.map(&:to_h).filter_map { |member| member["access_level"] if member["id"] == user_id.to_i }.max
    rescue Forbidden
      nil
    end

    def translating(not_found: :forbidden)
      yield
    rescue ::Gitlab::Error::Unauthorized
      raise InvalidToken, "GitLab does not accept this user token"
    rescue ::Gitlab::Error::NotFound
      not_found == :forbidden ? raise(Forbidden, "GitLab refused the request") : not_found
    rescue ::Gitlab::Error::Forbidden, ::Gitlab::Error::BadRequest, ::Gitlab::Error::MethodNotAllowed,
           ::Gitlab::Error::Conflict, ::Gitlab::Error::Unprocessable
      raise Forbidden, "GitLab refused the request"
    rescue ::Gitlab::Error::Error
      raise Unavailable, "GitLab is unavailable"
    rescue *TokenService::NETWORK_ERRORS => e
      raise Unavailable, "GitLab is unavailable (#{e.class.name.demodulize})"
    end
  end
end
