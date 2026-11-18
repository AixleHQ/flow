# frozen_string_literal: true

module PullRequests
  # A Forge pull-request event of one installation: the repositories of its
  # bound connections, and for a comment, the comment itself, which the event
  # does not carry. Forge gives an event five seconds, so this runs here.
  class ProcessBitbucketEventJob < ApplicationJob
    queue_as :default

    def perform(installation_id:, payload:)
      installation = BitbucketInstallation.find_by(id: installation_id)
      uuid = Bitbucket::Events.repository_uuid(payload)
      return if installation.nil? || uuid.nil?

      repositories = Repository.joins(:integration).merge(Integration.active)
                               .where(integration_id: installation.integrations.select(:id), external_id: uuid)
                               .preload(:integration, :scope).to_a
      repositories = EventPipeline.awaited(repositories)
      return if repositories.empty?

      repository = repositories.first
      comment = fetch_comment(repository, payload) if Bitbucket::Events.comment?(payload)
      event = Bitbucket::Events.parse(payload, full_name: repository.full_name, comment: comment)
      EventPipeline.process(event, repositories) if event
    end

    private

    def fetch_comment(repository, payload)
      ::Bitbucket::Api.for(repository.integration).comment(repository.external_organization_id, repository.external_id,
                                                         Bitbucket::Events.pull_request_id(payload),
                                                         Bitbucket::Events.comment_id(payload))
    rescue ::Bitbucket::Error => e
      Rails.logger.warn("[PullRequests::ProcessBitbucketEventJob] comment of repository #{repository.id}: #{e.message}")
      nil
    end
  end
end
