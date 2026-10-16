# frozen_string_literal: true

module Bitbucket
  module Forge
    # Whether an Atlassian account administers the workspace an installation is
    # on. The settings page may be seen by people who are not administrators,
    # and connecting a workspace to a company is an administrator's decision.
    module WorkspaceAdmin
      module_function

      def admin?(installation, account_id)
        return false unless account_id.to_s.match?(BitbucketPairing::ACCOUNT_ID)

        values, = AppClient.for(installation).page("workspaces", installation.workspace_uuid, "permissions",
                                                   params: { q: %(user.account_id="#{account_id}") })
        values.any? { |membership| membership["permission"] == "owner" && membership.dig("user", "account_id") == account_id }
      end
    end
  end
end
