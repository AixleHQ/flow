# frozen_string_literal: true

module Trackers
  class ProcessDeliveryJob < ApplicationJob
    queue_as :default
    retry_on EventPipeline::WriteInFlight, wait: EventPipeline::WRITE_RETRY_WAIT, attempts: EventPipeline::WRITE_RETRY_ATTEMPTS

    def perform(delivery_id)
      delivery = TrackerDelivery.find_by(id: delivery_id)
      return if delivery.nil? || delivery.status == "processed"

      integration = delivery.tracker_subscription.integration
      return delivery.update!(status: "skipped", detail: { "reason" => "integration inactive" }) unless integration.active?

      pipeline = EventPipeline.new(integration, wait_for_writes: executions < EventPipeline::WRITE_RETRY_ATTEMPTS)
      outside = delivery.notification_objects.count { |notification| !processed?(pipeline, notification) }
      delivery.update!(status: "processed", detail: outside.positive? ? { "outside_scope" => outside } : {})
    rescue Trackers::Error => e
      delivery&.update!(status: "failed", detail: { "error" => e.code, "message" => e.message.to_s.truncate(300) })
    end

    private

    # GitHub and Linear name an issue's board or team only on some events, so
    # such a delivery asks every tracked scope; the ones the issue is not in
    # answer not_found.
    def processed?(pipeline, notification)
      pipeline.process(notification)
      true
    rescue Trackers::Error => e
      raise unless e.code == "not_found"

      false
    end
  end
end
