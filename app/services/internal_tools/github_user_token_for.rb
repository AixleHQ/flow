# frozen_string_literal: true

module InternalTools
  # Platform tool: a GitHub token that acts as a named member of the company
  # (docs/design/github-user-identity.md §4.3). The named user needs the consent
  # that fits: "in my tasks" when they are the session's user, otherwise "in tasks
  # that aren't mine".
  class GithubUserTokenFor < Base
    include Concerns::GithubUserTokenContext

    tool do
      display_name "GitHub User Token For"
      description "Get a GitHub token that acts as a named member of this company, with the identity to commit " \
                  "with. Same token and limits as github_user_token. Works only for a person who connected their " \
                  "GitHub account and allowed it in this project: the switch for their own tasks when they are the " \
                  "person this session runs for, otherwise the switch for tasks that aren't theirs. Use the token " \
                  "in place and never print it."
      tags :github_identity
      requires_integration :github
      availability ->(_ctx) { Github::UserConnection.configured? }
      unavailable_message Concerns::GithubUserTokenContext::UNAVAILABLE
      read_only true
      destructive false
      idempotent false
      open_world true
      param :user_id, type: :integer, required: true,
                      description: "Id of the member to act as, from board_list_members or a task's assignee_id."
    end

    def execute
      return error(Concerns::UserTokenContext::NO_USER) if session_user.nil?

      return error(Concerns::UserTokenContext::NO_PROJECT) if project.nil?

      user = project.company.users.find_by(id: params[:user_id])
      return error("No member with id #{params[:user_id]} in this company.") if user.nil?

      issue_github_tokens(user: user, consent_scope: user.id == session_user.id ? :own : :others)
    end
  end
end
