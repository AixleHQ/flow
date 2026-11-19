# frozen_string_literal: true

module PullRequests
  module Github
    # The pull-request events of a GitHub App delivery. GitHub sends every
    # review and comment of every repository the App can see, so a delivery is
    # queued only for a repository a pull-request trigger waits on.
    module Webhooks
      module_function

      def receive(event, payload)
        parsed = Events.parse(event, payload)
        installation_id = Integer(payload.dig("installation", "id"), exception: false)
        full_name = payload.dig("repository", "full_name").to_s
        return if parsed.nil? || installation_id.nil? || full_name.blank?

        repositories = Repository.joins(:integration).merge(Integration.active)
                                 .where(integrations: { provider: "github", github_installation_id: installation_id })
                                 .where("LOWER(repositories.full_name) = ?", full_name.downcase)
        awaited = EventPipeline.awaited(repositories.to_a)
        ProcessEventJob.perform_later(repository_ids: awaited.map(&:id), event: parsed.to_job) if awaited.any?
      end
    end
  end
end
