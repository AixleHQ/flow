# frozen_string_literal: true

module Billing
  # The queue a rule in the seller account delivers subscription events into.
  #
  # The one AWS call in this feature that is NOT signed as the seller: the queue
  # lives in the account this application runs in, so the pod's own identity
  # reads it. Nothing here assumes a role.
  class MarketplaceEventsQueue
    class Error < StandardError; end

    # SQS takes at most ten at a time, and the queue is configured for long
    # polling, so an empty queue costs one held request rather than a spin.
    BATCH_SIZE = 10
    WAIT_SECONDS = 20

    # Bounds one drain. The backlog is normally nothing; this exists so a sweep
    # cannot run until the activity's timeout kills it mid-delete.
    MAX_BATCHES = 20

    DEFAULT_REGION = "us-east-1"

    def configured? = queue_url.present?

    # Yields each message body, parsed. Deletes only what the block took without
    # raising: a message whose handling failed is left to reappear after the
    # visibility timeout rather than being dropped.
    def each_message
      return 0 unless configured?

      handled = 0

      MAX_BATCHES.times do
        messages = receive
        break if messages.empty?

        messages.each do |message|
          yield parse(message.body)
          delete(message)
          handled += 1
        end
      end

      handled
    end

    private

    def receive
      client.receive_message(
        queue_url: queue_url,
        max_number_of_messages: BATCH_SIZE,
        wait_time_seconds: WAIT_SECONDS
      ).messages
    rescue ::Aws::SQS::Errors::ServiceError => e
      raise Error, "#{e.class.name.demodulize}: #{e.message}"
    end

    def delete(message)
      client.delete_message(queue_url: queue_url, receipt_handle: message.receipt_handle)
    rescue ::Aws::SQS::Errors::ServiceError => e
      raise Error, "#{e.class.name.demodulize}: #{e.message}"
    end

    # A body that is not JSON is not something redelivery will fix, so it is
    # answered as an empty envelope: recorded as unhandled and deleted.
    def parse(body)
      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def settings
      ::Settings.aws_marketplace&.saas || Hashie::Mash.new
    end

    def queue_url = settings.events_queue_url
    def region = settings.region.presence || DEFAULT_REGION

    def client
      @client ||= ::Aws::SQS::Client.new(region: region)
    end
  end
end
