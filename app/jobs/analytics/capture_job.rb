# frozen_string_literal: true

module Analytics
  # Sends one event. An event that still fails after a few tries is dropped:
  # analytics is never worth a growing queue.
  class CaptureJob < ApplicationJob
    queue_as :default

    retry_on Client::Error, wait: :polynomially_longer, attempts: 3 do |_job, error|
      Rails.logger.warn("[Analytics] event dropped: #{error.message}")
    end

    def perform(event)
      client = Client.new
      return unless client.configured?

      client.capture_batch([ event ])
    end
  end
end
