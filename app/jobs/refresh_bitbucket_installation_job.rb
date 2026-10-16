# frozen_string_literal: true

# Names a newly seen installation's workspace. The install event carries only
# its UUID, and the app's permissions can lag the event by minutes, so a refusal
# is left for the next heartbeat to retry.
class RefreshBitbucketInstallationJob < ApplicationJob
  queue_as :default

  def perform(installation_id)
    installation = BitbucketInstallation.live.find_by(id: installation_id)
    return unless installation

    workspace = Bitbucket::Forge::AppClient.for(installation).get("workspaces", installation.workspace_uuid)
    installation.update_columns(workspace_slug: workspace["slug"].presence, workspace_name: workspace["name"].presence,
                                updated_at: Time.current)
  rescue Bitbucket::Error => e
    Rails.logger.warn("[RefreshBitbucketInstallationJob] installation #{installation_id}: #{e.code}: #{e.message}")
  end
end
