# frozen_string_literal: true

module Feedback
  # Posts a finished text to the feedback channel, retried here so the request
  # that wrote it never waits on Slack.
  class SlackPostJob < ApplicationJob
    queue_as :default

    retry_on DeliveryFailed, wait: :polynomially_longer, attempts: 8

    def perform(text)
      SlackChannel.post(text)
    end
  end
end
