# frozen_string_literal: true

module Billing
  class SettleCancellationJob < ApplicationJob
    queue_as :default

    # How long a card the back-off could not stop waits before it is tried
    # again. Hours, not minutes: the back-off above has already spent hours.
    RETRY_STOPPING_AFTER = 6.hours

    # Stripe counted an event in about a minute on the sandbox; ten minutes is
    # room for a slow day, not for an outage.
    retry_on CancellationSettlement::NotYetCounted, wait: 20.seconds, attempts: 30 do |job, error|
      job.release(error)
    end

    # Stripe unreachable: back off for a few hours. The invoice is held as a
    # draft meanwhile, so waiting costs nothing but time.
    retry_on StripeClient::Error, wait: :polynomially_longer, attempts: 10 do |job, error|
      job.release(error)
    end

    def perform(cancellation_id)
      cancellation = BillingCancellation.find_by(id: cancellation_id)
      CancellationSettlement.new(cancellation).call if cancellation
    end

    # Out of attempts. A held invoice goes back to Stripe, which finalizes it
    # with what its meter has counted. A card not yet stopped is another
    # matter: it goes on billing a workspace that has left it, every month,
    # until somebody stops it -- so it is tried again later rather than given
    # up on, and reported each time round.
    def release(error)
      cancellation = BillingCancellation.find_by(id: arguments.first)
      return unless cancellation

      Rails.error.report(error, context: { billing_cancellation_id: cancellation.id })
      if cancellation.cancelling?
        cancellation.update!(settlement_error: error.message.to_s.truncate(1000))
        self.class.set(wait: RETRY_STOPPING_AFTER).perform_later(cancellation.id)
      else
        CancellationSettlement.new(cancellation).release!(error)
      end
    end
  end
end
