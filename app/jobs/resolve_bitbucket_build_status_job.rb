# frozen_string_literal: true

# A Forge build-status event, as a cue: the gates waiting on that repository and
# commit ask Bitbucket for the verdict (docs/design/bitbucket-integration.md §8).
class ResolveBitbucketBuildStatusJob < ApplicationJob
  queue_as :default

  def perform(repository_uuid:, commit:)
    return if repository_uuid.blank? || commit.blank?

    GateService.resolve_bitbucket_build_status(repository_uuid: repository_uuid, commit: commit)
  end
end
