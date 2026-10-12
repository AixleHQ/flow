# frozen_string_literal: true

module Billing
  class SettleCancellationJob < ApplicationJob
    queue_as :default

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

    def release(error)
      cancellation = BillingCancellation.find_by(id: arguments.first)
      return unless cancellation

      Rails.error.report(error, context: { billing_cancellation_id: cancellation.id })
      CancellationSettlement.new(cancellation).release!(error)
    end
  end
end
