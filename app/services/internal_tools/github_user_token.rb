# frozen_string_literal: true

module InternalTools
  # Platform tool: a GitHub token that acts as the session's user
  # (docs/design/github-user-identity.md §4.3). The platform provides the token and
  # the commit identity; a workflow's instructions decide how to use them.
  class GithubUserToken < Base
    include Concerns::GithubUserTokenContext

    tool do
      display_name "GitHub User Token"
      description "Get a GitHub token that acts as the person this session runs for, with the identity to commit " \
                  "with (login, id, name, noreply email). The token is limited to this session's GitHub App " \
                  "repositories and to contents:write and pull_requests:write, so it can push and open pull requests " \
                  "there as that person. One token per repository owner. It works only when the person connected " \
                  "their GitHub account and allowed agents to act as them in their own tasks in this project. " \
                  "Use the token in place and never print it."
      tags :github_identity
      requires_integration :github
      availability ->(_ctx) { Github::UserConnection.configured? }
      unavailable_message Concerns::GithubUserTokenContext::UNAVAILABLE
      read_only true
      destructive false
      idempotent false
      open_world true
    end

    def execute
      issue_github_tokens(user: session_user, consent_scope: :own)
    end
  end
end
