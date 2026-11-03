# frozen_string_literal: true

module Billing
  # Every subscription a company has had, as the Billing tab lists them: the
  # one paying now, and the ones that ended. There is no table of
  # subscriptions. A card that was stopped is the BillingCancellation that
  # stopped it, and an AWS Marketplace subscription is the licence AWS issued
  # for it, which the company keeps once it ends.
  class SubscriptionHistory
    AWS_BILLING_URL = "https://console.aws.amazon.com/billing/home#/bills"

    CARD_RUNNING = %w[active cancelling payment_failed].freeze
    LICENSE_STOPPED = %w[ending ended].freeze

    def initialize(company, price: CardPrice.new, now: Time.current)
      @company = company
      @price = price
      @now = now
    end

    attr_reader :company, :price, :now

    def to_h
      { active: active, previous: previous }
    end

    # AWS first: while a live licence bills, the card has no say. A licence
    # that is closing is already among the stopped ones, as the banner says.
    def active
      license = company.marketplace_license
      return running_license(license) if company.billing_payer.aws_marketplace? && license&.active?
      return running_card if company.stripe_subscription_id.present? && company.billing_status.in?(CARD_RUNNING)

      nil
    end

    def previous
      (stopped_cards + stopped_licenses).sort_by { |entry| -entry[:cancelled_at].to_i }
    end

    private

    def running_card
      since = company.billing_period_starts_at
      entry(kind: "card", status: company.billing_status,
            period_starts_at: since, period_ends_at: company.billing_period_ends_at,
            next_invoice_at: company.billing_period_ends_at, cancels_at: company.billing_cancels_at,
            usage: since && card_usage(since, now))
    end

    # A scheduled cancellation still pending, which only companies that
    # cancelled before cancelling became immediate have, is the running card's
    # business, not a subscription that ended.
    def stopped_cards
      company.billing_cancellations
             .where(resumed_at: nil)
             .where("settlement_state IS NOT NULL OR cancels_at <= ?", now)
             .order(cancels_at: :desc)
             .map { |cancellation| stopped_card(cancellation) }
    end

    # The period the final invoice covers starts where the last period did. A
    # row from before that was recorded knows only the hours it still owed.
    def stopped_card(cancellation)
      since = cancellation.period_started_at || cancellation.final_usage_by_hour.keys.min
      entry(kind: "card", status: "cancelled",
            period_starts_at: cancellation.started_at, period_ends_at: cancellation.cancels_at,
            cancelled_at: cancellation.cancels_at,
            usage: since && card_usage(since, cancellation.cancels_at),
            invoices_url: cancellation.final_invoice_url,
            final_invoice: cancellation.settlement_state &&
              { state: cancellation.settlement_state, url: cancellation.final_invoice_url })
    end

    # Read from our own ledger, which is what the meter sends Stripe: the same
    # minutes, an hour behind at most, since an hour is recorded once it closes.
    def card_usage(from, to)
      rows = CompanyCapacityUsage.where(company_id: company.id, period_start: from...to)
      minutes = BigDecimal(rows.sum(:quantity_seconds)) / 60
      last_hour = rows.maximum(:period_start)

      { since: from, until: to, worker_minutes: minutes.round(1).to_f,
        measured_until: last_hour && (last_hour + 1.hour), estimate: price.estimate(minutes) }
    end

    # AWS invoices a calendar month at a time.
    def running_license(license)
      month = now.utc.beginning_of_month
      entry(kind: "aws_marketplace", status: "active",
            period_starts_at: month, period_ends_at: month.next_month, next_invoice_at: month.next_month,
            usage: license_usage(license, since: [ month, license.subscribed_at ].compact.max, until_time: now,
                                          reported_in: month...month.next_month),
            invoices_url: AWS_BILLING_URL, aws_account_id: license.customer_aws_account_id)
    end

    def stopped_licenses
      company.marketplace_licenses.where(subscription_state: LICENSE_STOPPED).map { |license| stopped_license(license) }
    end

    # The final usage is the month the subscription ended in: that is the AWS
    # bill it lands on.
    def stopped_license(license)
      cancelled_at = license.ended_at || closed_at(license) || now
      month = cancelled_at.utc.beginning_of_month
      entry(kind: "aws_marketplace", status: "cancelled",
            period_starts_at: license.subscribed_at, period_ends_at: cancelled_at, cancelled_at: cancelled_at,
            usage: license_usage(license, since: [ month, license.subscribed_at ].compact.max, until_time: cancelled_at,
                                          reported_in: month...month.next_month),
            invoices_url: AWS_BILLING_URL, aws_account_id: license.customer_aws_account_id)
    end

    # Nothing records when a licence entered `ending`; the event that closed it
    # is the nearest thing.
    def closed_at(license)
      MarketplaceSubscriptionEvent.where(marketplace_license_id: license.id, detail_type: MarketplaceEvents::ENDED)
                                  .minimum(:occurred_at)
    end

    # What AWS has actually been sent for this licence, keyed by AWS's receipt
    # so the final meter's repeat counts once. Not the offered ledger: that
    # holds minutes the card was billed for before a handover, minutes not yet
    # sent, and fractions. Both paths that send are read, because
    # Billing::MarketplaceFinalMeter writes no ledger row.
    def license_usage(license, since:, until_time:, reported_in:)
      receipts = hourly_receipts(license, reported_in).merge(final_meter_receipts(license, reported_in))
      minutes = BigDecimal(receipts.values.sum)

      { since: since, until: until_time, worker_minutes: minutes.to_f, measured_until: nil,
        estimate: license_estimate(license, minutes) }
    end

    # Priced at what the agreement was accepted at -- a private offer's rate,
    # not the listing's -- by the whole minute, as AWS bills the dimension.
    # Nothing where the licence never learned its price.
    def license_estimate(license, minutes)
      return nil if license.price_per_minute.nil?

      { amount_cents: (minutes * license.price_per_minute * 100).round.to_i,
        currency: license.price_currency.to_s.downcase.presence || "usd",
        unit_amount_cents: (license.price_per_minute * 100).to_f, minutes_per_unit: 1 }
    end

    # Receipt -> minutes, floored the way the adapter floors what it sends.
    def hourly_receipts(license, window)
      CapacityMeterReport
        .where(provider: Meter::AwsMarketplaceSaas.provider, period_start: window)
        .pluck(:breakdown, :receipts)
        .each_with_object({}) do |(breakdown, receipts), map|
          id = receipts[license.license_arn]
          next if id.blank? || id == Meter::AwsMarketplaceSaas::DISPUTED

          map[id] = (BigDecimal(breakdown[company.id.to_s].to_s.presence || "0") / 60).floor
        end
    end

    def final_meter_receipts(license, window)
      MarketplaceSubscriptionEvent
        .where(marketplace_license_id: license.id, occurred_at: window)
        .pluck(:metered_receipts)
        .each_with_object({}) { |receipts, map| map.merge!(receipts.to_h) }
    end

    def entry(kind:, status:, period_starts_at: nil, period_ends_at: nil, next_invoice_at: nil, cancels_at: nil,
              cancelled_at: nil, usage: nil, invoices_url: nil, aws_account_id: nil, final_invoice: nil)
      { kind: kind, status: status, period_starts_at: period_starts_at, period_ends_at: period_ends_at,
        next_invoice_at: next_invoice_at, cancels_at: cancels_at, cancelled_at: cancelled_at, usage: usage,
        invoices_url: invoices_url, aws_account_id: aws_account_id, final_invoice: final_invoice }
    end
  end
end
