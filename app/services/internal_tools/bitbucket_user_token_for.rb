# frozen_string_literal: true

module InternalTools
  # Platform tool: a Bitbucket token that acts as a named member of the company
  # (docs/design/bitbucket-user-identity.md §4.2). The named user needs the consent
  # that fits: "in my tasks" when they are the session's user, otherwise "in tasks
  # that aren't mine".
  class BitbucketUserTokenFor < Base
    include Concerns::BitbucketUserTokenContext

    tool do
      display_name "Bitbucket User Token For"
      description "Get a Bitbucket token that acts as a named member of this company, with the identity to commit " \
                  "with. Same token and limits as bitbucket_user_token. Works only for a person who connected " \
                  "their Bitbucket account and allowed it in this project: the switch for their own tasks when " \
                  "they are the person this session runs for, otherwise the switch for tasks that aren't theirs. " \
                  "Use the token in place and never print it."
      tags :bitbucket_identity
      requires_integration :bitbucket
      availability ->(_ctx) { Bitbucket::UserConnection.configured? }
      unavailable_message Concerns::BitbucketUserTokenContext::UNAVAILABLE
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

      issue_bitbucket_tokens(user: user, consent_scope: user.id == session_user.id ? :own : :others)
    end
  end
end
