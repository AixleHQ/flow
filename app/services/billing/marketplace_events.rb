# frozen_string_literal: true

module Billing
  # Takes what AWS puts on the queue and moves the licence it is about.
  #
  # Recording and applying are separate on purpose. An event can arrive before
  # the licence it names exists -- the agreement is created when the buyer
  # subscribes, the licence row when they reach the fulfilment page -- so
  # everything is recorded first and applied whenever it can be, including long
  # afterwards.
  class MarketplaceEvents
    SOURCE = "aws.agreement-marketplace"

    # Spelled as AWS sends them. We extend offers directly, which makes us both
    # manufacturer and proposer, and AWS then sends only the proposer copy of
    # the agreement events while the licence events stay manufacturer.
    CREATED = "Purchase Agreement Created - Proposer"
    AMENDED = "Purchase Agreement Amended - Proposer"
    ENDED = "Purchase Agreement Ended - Proposer"
    LICENSE_UPDATED = "License Updated - Manufacturer"
    LICENSE_DEPROVISIONED = "License Deprovisioned - Manufacturer"

    HANDLED = [ CREATED, AMENDED, ENDED, LICENSE_UPDATED, LICENSE_DEPROVISIONED ].freeze

    # What AWS allows for reporting a cancelling customer's last usage, counted
    # from the event. After it, a record is refused however correct it is.
    FINAL_WINDOW = 1.hour

    def initialize(final_meter: MarketplaceFinalMeter.new)
      @final_meter = final_meter
    end

    attr_reader :final_meter

    # One envelope off the queue. Answers the stored row, or nil for anything
    # that is not ours to act on -- another product's event, or a type we do
    # not handle, both of which are deleted rather than left to redeliver.
    def record(envelope)
      return nil unless envelope["source"] == SOURCE
      return nil unless envelope["detail-type"].in?(HANDLED)

      detail = envelope["detail"] || {}
      return nil unless ours?(detail)

      MarketplaceSubscriptionEvent.create!(
        event_id: envelope["id"],
        detail_type: envelope["detail-type"],
        agreement_id: detail.dig("agreement", "id"),
        license_arn: detail.dig("license", "arn"),
        occurred_at: envelope["time"],
        detail: detail
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Redelivery. The first copy is already stored and may already be applied.
      MarketplaceSubscriptionEvent.find_by(event_id: envelope["id"])
    end

    # Everything recorded and not yet applied, oldest first. Answers how many
    # moved, which is what the activity reports.
    def apply_pending
      applied = 0

      MarketplaceSubscriptionEvent.unapplied.in_order.find_each do |event|
        applied += 1 if apply(event)
      end

      applied
    end

    # Called when a licence is created, so events that beat the buyer to the
    # page are applied at once rather than waiting for the next sweep.
    def apply_for(license)
      MarketplaceSubscriptionEvent.awaiting(license).in_order.each { |event| apply(event) }
      license.reload
    end

    # False when there is nothing to apply it to yet, which is not a failure:
    # the row stays unapplied and the next sweep tries again.
    def apply(event)
      license = license_for(event)
      return false if license.nil?

      event.applied!(license, metered: move(license, event))
      true
    rescue StandardError => e
      event.failed!(e.message)
      false
    end

    private

    # The rule in the seller account matches a source and a detail type, not a
    # product, so every agreement this account sells arrives here -- other
    # listings, other buyers, other teams. Theirs would never match a licence
    # and would be retried by every sweep for ever.
    #
    # An event that names no product at all is kept: better a row nobody
    # matches than a dropped one that was ours.
    def ours?(detail)
      product = detail["product"] || {}
      named = product.values_at("id", "code").compact
      return true if named.empty?

      named.intersect?([ product_id, product_code ].compact)
    end

    def settings = ::Settings.aws_marketplace&.saas || Hashie::Mash.new
    def product_id = settings.product_id.presence
    def product_code = settings.product_code.presence

    def license_for(event)
      by_arn = MarketplaceLicense.find_by(license_arn: event.license_arn) if event.license_arn.present?
      return by_arn if by_arn

      MarketplaceLicense.find_by(agreement_id: event.agreement_id) if event.agreement_id.present?
    end

    # Answers what was metered, if anything, so the caller can record it.
    def move(license, event)
      case event.detail_type
      when CREATED then confirm(license, event)
      when AMENDED, LICENSE_UPDATED then store(license, event)
      when ENDED then close(license, event)
      when LICENSE_DEPROVISIONED then deprovision(license, event)
      end
    end

    # The machine refuses what the order of delivery would otherwise allow: a
    # creation that overtook a cancellation does not reopen the subscription.
    def confirm(license, event)
      store(license, event)
      license.confirm! if license.may_confirm?
      start(license.company)
    end

    # The workspace is created blocked when the licence is still pending, which
    # happens when the buyer reaches the page before AWS will say the agreement
    # is live. Nothing else lifts that, so a confirmation arriving afterwards
    # has to -- otherwise the customer pays for a workspace that never starts.
    def start(company)
      return if company.nil? || company.billing_block_reason != "awaiting_subscription"

      company.update!(billing_state: "active", billing_block_reason: nil)
    end

    def store(license, event)
      offer = event.detail.dig("offer", "id")
      license.update!(offer_identifier: offer) if offer.present? && offer != license.offer_identifier
    end

    # Not the metering deadline, whatever it looks like: AWS opens the final
    # window on the deprovisioning event, not here. The company loses access
    # now and the licence stays meterable until that event arrives.
    #
    # But the usage goes first, because stopping the company is what makes it
    # unmeasurable: CapacityWindow offers a blocked company nothing, and it
    # does so for the WHOLE hour, including the part it was running. Measured
    # afterwards there is nothing left to find. Billing::FinalUsage says the
    # same thing for Stripe in its first line; this path was written again and
    # walked into it.
    def close(license, event)
      meter_the_last_usage(license, event)
    ensure
      license.close! if license.may_close?
      block(license.company)
    end

    # The one hour AWS allows starts here, and the hourly schedule cannot serve
    # it: an hour reported at five past the next hour is already outside the
    # window for any licence deprovisioned after its first five minutes. So the
    # usage goes now, before the state moves -- `finish!` makes it unmeterable.
    # Metered again, and that is not waste: the two events arrive seconds apart
    # and in one drain, so whichever runs first is the one that catches the
    # hour. AWS answers the second copy DuplicateRecord, which the adapter
    # counts as accepted.
    def deprovision(license, event)
      meter_the_last_usage(license, event)
    ensure
      license.finish! if license.may_finish?
      block(license.company)
    end

    # AWS gives one hour from the event, and a call that never reached AWS has
    # sent nothing -- so it is raised, which leaves the event unapplied and the
    # next sweep tries again a minute later. The state still moves, through the
    # `ensure` above: a customer who has cancelled does not keep the workspace
    # because our credentials are broken.
    #
    # Bounded by the window itself. Once it has shut no retry can be accepted,
    # so the attempt stops and says so rather than being made every minute for
    # ever.
    def meter_the_last_usage(license, event)
      final_meter.call(license)
    rescue MarketplaceSellerClient::Error => e
      raise if event.occurred_at > FINAL_WINDOW.ago

      "unsent: #{e.message} (the one-hour window shut)"
    end

    def block(company)
      return if company.nil? || company.billing_blocked?

      company.update!(billing_state: "blocked", billing_block_reason: "canceled")
    end
  end
end
