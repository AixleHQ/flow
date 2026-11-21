# frozen_string_literal: true

module InternalTools
  # Platform tool: a Bitbucket token that acts as the session's user
  # (docs/design/bitbucket-user-identity.md §4.2). The platform provides the token and
  # the commit identity; a workflow's instructions decide how to use them.
  class BitbucketUserToken < Base
    include Concerns::BitbucketUserTokenContext

    tool do
      display_name "Bitbucket User Token"
      description "Get a Bitbucket token that acts as the person this session runs for, with the identity to " \
                  "commit with (nickname, account id, name, email). The token is the person's own OAuth token: " \
                  "Bitbucket cannot limit it to this session's repositories, so it can do whatever that person " \
                  "can on Bitbucket. Only the repositories of this session they can push to are listed; use it " \
                  "there only. It works only when the person connected their Bitbucket account and allowed " \
                  "agents to act as them in their own tasks in this project. Use the token in place and never " \
                  "print it."
      tags :bitbucket_identity
      requires_integration :bitbucket
      availability ->(_ctx) { Bitbucket::UserConnection.configured? }
      unavailable_message Concerns::BitbucketUserTokenContext::UNAVAILABLE
      read_only true
      destructive false
      idempotent false
      open_world true
    end

    def execute
      issue_bitbucket_tokens(user: session_user, consent_scope: :own)
    end
  end
end
