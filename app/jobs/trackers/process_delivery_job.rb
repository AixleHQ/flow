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
      delivery.notification_objects.each { |notification| pipeline.process(notification) }
      delivery.update!(status: "processed")
    rescue Trackers::Error => e
      delivery&.update!(status: "failed", detail: { "error" => e.code, "message" => e.message.to_s.truncate(300) })
    end
  end
end
