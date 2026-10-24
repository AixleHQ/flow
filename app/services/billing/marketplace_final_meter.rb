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
  # Sending an hour the schedule will send again is safe and expected: AWS keys
  # a record on (licence, dimension, hour), so the repeat bills nothing.
  # Sending nothing is the failure that cannot be recovered, because the window
  # does not reopen. So this errs towards sending.
  #
  # What it does not do is send an hour we already hold AWS's receipt for.
  # Observed on 24 October: AWS answered such a repeat with `Success` and the
  # *same* `MeteringRecordId` rather than `DuplicateRecord`, so the line read
  # `sent=2:already=0:minutes=72` when sixty of those minutes had already been
  # billed. The receipt is the only thing that tells the two apart.
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

    # Answers a line saying what it did, which the caller records against the
    # event that caused it. The hourly meter has a ledger row for this; without
    # one here, whether the last hour of a cancelling customer was billed could
    # only be read off their own invoice, hours later.
    #
    # Deliberately does not raise on a refusal: the caller's next step is to end
    # the licence, and a licence left open because its last minutes were refused
    # would go on being billed by the schedule for an entitlement AWS has
    # already revoked. The refusal goes in the line instead.
    def call(license)
      return NOTHING unless license.meterable? && client.configured?

      usages = usages_for(license)
      return NOTHING if usages.empty?

      summary(usages, client.batch_meter_usage(usages))
    rescue MarketplaceSellerClient::Error => e
      "refused: #{e.message}"
    end

    private

    # Minutes as well as counts: the whole point of this path is the part-hour
    # the schedule cannot reach, and a reader needs to see that it was not zero.
    def summary(usages, outcomes)
      already = outcomes.count(&:duplicate?)
      refused = outcomes.reject(&:accepted?)
      line = "sent=#{outcomes.size - already}:already=#{already}:minutes=#{usages.sum(&:quantity)}"
      # AWS's own receipt, which is the only evidence of acceptance that is not
      # our own word. One line is enough here: this path sends a licence's last
      # hour or two, never a batch.
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

    # Hours the schedule already holds AWS's receipt for, as epoch seconds —
    # compared that way because the column comes back as a TimeWithZone and
    # `Array#-` would not match it against a Time.
    #
    # Re-sending such an hour is harmless, which is why it was left alone: AWS
    # keys a record on (licence, dimension, hour). It is the *line* that was
    # wrong. On 24 October a cancellation reported `sent=2:already=0:minutes=72`
    # when only twelve of those minutes were new, because AWS answered the
    # repeat with the same `MeteringRecordId` and `Success` rather than
    # `DuplicateRecord`, so `already` never counted it. A reader cannot tell a
    # replay from a second charge on AWS's answer alone; they can tell it from
    # the receipt we already hold.
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
