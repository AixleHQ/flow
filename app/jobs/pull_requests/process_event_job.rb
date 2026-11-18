# frozen_string_literal: true

module PullRequests
  # Publishes a pull-request event a receiver accepted, out of the provider's
  # delivery timeout.
  class ProcessEventJob < ApplicationJob
    queue_as :default

    def perform(repository_ids:, event:)
      repositories = Repository.where(id: repository_ids).preload(:integration, :scope).to_a
      return if repositories.empty?

      EventPipeline.process(Event.from_job(event), repositories)
    end
  end
end
