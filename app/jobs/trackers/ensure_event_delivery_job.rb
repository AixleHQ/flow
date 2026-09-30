# frozen_string_literal: true

module Trackers
  # A tracker trigger was created or enabled: make sure its tracker delivers the
  # events it waits for. Out of the request, because it calls the provider.
  class EnsureEventDeliveryJob < ApplicationJob
    queue_as :default

    def perform(project_tracker_id)
      tracker = ProjectTracker.find_by(id: project_tracker_id)
      return unless tracker&.usable?

      tracker.tracker_provider.ensure_event_delivery!
    rescue Trackers::Error, ::AzureDevops::Error => e
      Rails.logger.warn("[Trackers::EnsureEventDeliveryJob] tracker #{project_tracker_id}: #{e.message}")
    end
  end
end
