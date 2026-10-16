# frozen_string_literal: true

# A repository changed in Bitbucket — renamed or moved, perhaps. Rows are
# addressed by UUID, so the readable name and the clone URL are re-read and kept
# in step; nothing else about the row depends on them.
class RefreshBitbucketRepositoryJob < ApplicationJob
  queue_as :default

  def perform(installation_id:, repository_uuid:)
    installation = BitbucketInstallation.live.find_by(id: installation_id)
    uuid = Bitbucket::Forge::Ids.uuid(repository_uuid)
    return unless installation && uuid

    rows = Repository.joins(:integration)
                     .where(integrations: { bitbucket_installation_id: installation.id }, external_id: uuid)
    return unless rows.exists?

    full_name = Bitbucket::Forge::AppClient.for(installation)
                                           .get("repositories", installation.workspace_uuid, uuid)["full_name"].to_s
    return unless full_name.match?(Repository::FULL_NAME_FORMAT)

    rows.where.not(full_name: full_name).find_each do |repository|
      next if repository.update(full_name: full_name, clone_url: "#{Bitbucket::AppConfig::WEB_HOST}/#{full_name}.git")

      Rails.logger.warn("[RefreshBitbucketRepositoryJob] repository #{repository.id} kept #{repository.full_name_was}: " \
                        "#{repository.errors.full_messages.to_sentence}")
    end
  rescue Bitbucket::Error => e
    Rails.logger.warn("[RefreshBitbucketRepositoryJob] #{repository_uuid}: #{e.code}: #{e.message}")
  end
end
