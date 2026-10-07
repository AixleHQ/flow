# frozen_string_literal: true

module Slack
  # Who a Slack sender is in Aixle (docs/design/teams-integration.md §21): the
  # account that linked that Slack account, as long as it may still sign in.
  # Never by email.
  module Sender
    module_function

    def user(team_id, slack_user_id)
      id = ChatIdentity.user_id_for(provider: Chat::SlackProvider::KEY, workspace_id: team_id,
                                    external_user_id: slack_user_id)
      id && User.authenticatable.find_by(id: id)
    end
  end
end
