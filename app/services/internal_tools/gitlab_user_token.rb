# frozen_string_literal: true

module InternalTools
  # Platform tool: a GitLab token that acts as the session's user
  # (docs/design/gitlab-user-identity.md §4.2). The platform provides the token and
  # the commit identity; a workflow's instructions decide how to use them.
  class GitlabUserToken < Base
    include Concerns::GitlabUserTokenContext

    tool do
      display_name "GitLab User Token"
      description "Get a GitLab token that acts as the person this session runs for, with the identity to commit " \
                  "with (username, id, name, email). The token is the person's own OAuth token with the api scope: " \
                  "GitLab cannot limit it to this session's repositories, so it can do whatever that person can on " \
                  "GitLab. Only the repositories of this session they can push to are listed; use it there only. " \
                  "It works only when the person connected their GitLab account and allowed agents to act as them " \
                  "in their own tasks in this project. Use the token in place and never print it."
      tags :gitlab_identity
      requires_integration :gitlab
      availability ->(_ctx) { Gitlab::UserConnection.configured? }
      unavailable_message Concerns::GitlabUserTokenContext::UNAVAILABLE
      read_only true
      destructive false
      idempotent false
      open_world true
    end

    def execute
      issue_gitlab_tokens(user: session_user, consent_scope: :own)
    end
  end
end
