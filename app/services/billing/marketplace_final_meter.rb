# frozen_string_literal: true

module Billing
  # The last usage of one licence, sent the moment AWS opens the window for it.
  #
  # The hourly schedule cannot serve this. It runs at five past and reports the
  # hour that has just closed, while AWS gives one hour from the deprovisioning
  # event: a licence deprovisioned at 10:02 has its 10:00-10:02 offered at
  # 11:05, inside the window by five minutes, and one deprovisioned at 10:20 has
  # it offered after the window shut. So this is the only metering in the design
  # that is event-driven rather than periodic.
  #
  # Sending an hour the schedule will send again is safe: AWS keys a record on
  # (licence, dimension, hour), so the repeat bills nothing. Sending nothing
  # cannot be recovered, because the window does not reopen. So this errs
  # towards sending -- except for an hour we already hold AWS's receipt for,
  # which AWS would answer `Success` with the same `MeteringRecordId`, so that
  # a line counting what was sent would read as a second charge.
  class MarketplaceFinalMeter
    # The hour under way and the one before it. The earlier one is included
    # because the schedule may not have reached it yet -- it reports an hour at
    # five past the next one, and a licence can be deprovisioned in those five
    # minutes.
    HOURS_BACK = 1

    def initialize(client: MarketplaceSellerClient.new)
      @client = client
    end

    attr_reader :client

    NOTHING = "nothing to send"

    # What one call did: the line a reader sees, and AWS's receipts with the
    # minutes each bought. Structured because this path writes no ledger row,
    # so the receipts are the only record these minutes reached AWS; keyed by
    # receipt id, which counts the two cancellation events' repeat once.
    Sent = Data.define(:line, :receipts) do
      def to_s = line
    end

    # Answers what it did, which the caller records against the event. Raises
    # when the call did not happen -- credentials, throttling -- so the event
    # stays unapplied and is tried again inside AWS's window. A refusal of a
    # *record* is not this: AWS answers those in the batch, and they go in the
    # line.
    def call(license)
      return Sent.new(line: NOTHING, receipts: {}) unless license.meterable? && client.configured?

      usages = usages_for(license)
      return Sent.new(line: NOTHING, receipts: {}) if usages.empty?

      outcomes = client.batch_meter_usage(usages)
      Sent.new(line: summary(usages, outcomes), receipts: receipts_for(usages, outcomes))
    end

    private

    # Receipt -> the minutes it bought. Only records AWS honoured: a refused one
    # carries no id, and counting it would say an hour was billed that was not.
    def receipts_for(usages, outcomes)
      usages.zip(outcomes).each_with_object({}) do |(usage, outcome), map|
        next if outcome.nil? || outcome.metering_record_id.blank?

        map[outcome.metering_record_id] = usage.quantity
      end
    end

    # Minutes as well as counts, and AWS's receipt: the only evidence of
    # acceptance that is not our own word.
    def summary(usages, outcomes)
      already = outcomes.count(&:duplicate?)
      refused = outcomes.reject(&:accepted?)
      line = "sent=#{outcomes.size - already}:already=#{already}:minutes=#{usages.sum(&:quantity)}"
      receipts = outcomes.filter_map(&:metering_record_id)
      line += ":receipt=#{receipts.join(',')}" if receipts.any?
      return line if refused.empty?

      "#{line}:refused=#{refused.map(&:status).join(',')}"
    end

    def usages_for(license)
      now = Time.current.utc
      wanted = hours(now)
      done = receipted_hours(license, wanted)

      wanted.filter_map do |hour|
        next if done.include?(hour.to_i)

        minutes = minutes_for(license.company_id, hour, now)
        next if minutes.zero?

        MarketplaceSellerClient::Usage.new(
          license_arn: license.license_arn,
          customer_aws_account_id: license.customer_aws_account_id,
          dimension: Meter::AwsMarketplaceSaas::DIMENSION,
          quantity: minutes,
          occurred_at: hour
        )
      end
    end

    def hours(now)
      current = now.beginning_of_hour
      (0..HOURS_BACK).map { |back| current - back.hours }
    end

    # Hours the schedule already holds AWS's receipt for, as epoch seconds: the
    # column comes back as a TimeWithZone and `Array#-` would not match it
    # against a Time.
    def receipted_hours(license, hours)
      CapacityMeterReport
        .where(provider: Meter::AwsMarketplaceSaas.provider, period_start: hours, state: "reported")
        .pluck(:period_start, :receipts)
        .filter_map { |period_start, receipts| period_start.to_i if receipts[license.license_arn].present? }
        .to_set
    end

    # `until_time` is what makes the hour under way measurable at all: the
    # window otherwise measures a closed hour, and this one has not closed.
    def minutes_for(company_id, hour, now)
      window = CapacityWindow.for_hour(hour, until_time: now, company_ids: [ company_id ])

      (window.per_company[company_id].to_i / 60.0).floor
    end
  end
end
