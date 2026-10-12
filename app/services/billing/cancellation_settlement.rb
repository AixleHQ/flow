# frozen_string_literal: true

module Billing
  # Puts everything a cancelled company used on its final invoice, then issues
  # that invoice.
  #
  # Stripe makes the final invoice at the moment of cancelling, as a draft it
  # finalizes on its own an hour later, and it reads the meter again when it
  # finalizes. Measured on the sandbox (2026-10-12, flow board #174): an event
  # sent after the cancellation, timestamped before it, lands on that invoice —
  # but only once Stripe has counted it, which took about a minute, and an
  # invoice finalized before then never bills it. So the invoice is held, the
  # usage is sent, the meter is asked until it agrees, and only then is the
  # invoice finalized and charged.
  class CancellationSettlement
    # Raised until Stripe's meter shows every hour that was sent; the job
    # retries on it.
    NotYetCounted = Class.new(StandardError)

    # Stripe sums decimals it was sent as strings; this is room for its
    # rounding, three orders below the smallest amount ever sent.
    TOLERANCE = BigDecimal("0.001")

    def initialize(cancellation, client: StripeClient.new)
      @cancellation = cancellation
      @client = client
    end

    attr_reader :cancellation, :client

    def call
      return unless cancellation.settling?

      client.hold_invoice(invoice_id: invoice_id) if invoice_id
      send_usage
      uncounted = uncounted_hours
      raise NotYetCounted, "Stripe has not counted #{uncounted.map(&:iso8601).join(', ')} yet" if uncounted.any?

      invoice = invoice_id && client.issue_invoice(invoice_id: invoice_id)
      cancellation.update!(settlement_state: "settled", settled_at: Time.current, settlement_error: nil,
                           final_invoice_url: invoice&.hosted_invoice_url)
    end

    # When the job has run out of attempts: Stripe finalizes the invoice itself,
    # with whatever its meter has counted by then. Less than the whole usage,
    # perhaps, but an invoice held forever bills nothing at all.
    def release!(error)
      cancellation.update!(settlement_state: "failed", settlement_error: error.message.to_s.truncate(1000))
      client.release_invoice(invoice_id: invoice_id) if invoice_id
    end

    private

    def invoice_id = cancellation.final_invoice_id.presence

    def company = cancellation.company

    def send_usage
      cancellation.final_usage_by_hour.each do |hour, seconds|
        client.send_meter_event(
          customer_id: company.stripe_customer_id,
          minutes: minutes(seconds),
          occurred_at: hour,
          identifier: StripeClient.idempotency_key("capacity", company.id, hour.to_i)
        )
      end
    end

    def uncounted_hours
      cancellation.final_usage_by_hour.filter_map do |hour, seconds|
        counted = client.metered_minutes(customer_id: company.stripe_customer_id, from: hour, to: hour_end(hour))
        hour if counted < minutes(seconds) - TOLERANCE
      end
    end

    # Stripe takes minute boundaries. The end stops at the next minute rather
    # than the end of an hour still under way: that is the shape tried against
    # the sandbox.
    def hour_end(hour)
      now = Time.current
      next_minute = now.beginning_of_minute == now ? now : now.beginning_of_minute + 1.minute
      [ hour + 1.hour, next_minute ].min
    end

    def minutes(seconds) = (BigDecimal(seconds) / 60).round(4)
  end
end
