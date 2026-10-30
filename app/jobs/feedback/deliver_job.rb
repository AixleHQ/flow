# frozen_string_literal: true

module Feedback
  # One destination per job, so a Slack outage retried here never makes a second card.
  class DeliverJob < ApplicationJob
    queue_as :default

    retry_on DeliveryFailed, wait: :polynomially_longer, attempts: 8
    discard_on ActiveJob::DeserializationError

    def perform(submission, destination)
      Feedback.destinations.fetch(destination).new(submission).deliver
    end
  end
end
