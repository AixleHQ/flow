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

    # Raised when AWS cannot say whether the agreement a licence holds is
    # still live, which is the one question a deprovisioning after a renewal
    # turns on. The event is left for the next sweep rather than guessed at.
    Unread = Class.new(StandardError)

    def initialize(final_meter: MarketplaceFinalMeter.new, client: MarketplaceSellerClient.new)
      @final_meter = final_meter
      @client = client
    end

    attr_reader :final_meter, :client

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

      MarketplaceSubscriptionEvent.worth_sweeping.in_order.find_each do |event|
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

      if superseded?(license, event)
        event.applied!(license, metered: "ignored: about agreement #{event.agreement_id.presence || 'unnamed'}, " \
                                         "which #{license.agreement_id} replaced")
        return true
      end

      sent = move(license, event)
      event.applied!(license, metered: sent.to_s.presence, receipts: sent.try(:receipts) || {})
      true
    rescue StandardError => e
      event.failed!(e.message)
      false
    end

    private

    # The rule in the seller account matches a source and a detail type, not a
    # product, so every listing this account sells arrives here. An event that
    # names no product is kept: better a row nobody matches than a dropped one
    # that was ours.
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
      return license_named_by(event) if event.license_arn.present?
      return nil if event.agreement_id.blank?

      MarketplaceLicense.find_by(agreement_id: event.agreement_id) || by_previous_agreement(event)
    end

    # A licence event names its licence. A `License Updated` naming an ARN
    # nobody holds, under an agreement a live row does hold, is the licence a
    # renewal or replacement issued for that agreement: the row is that
    # licence's now (see #store). A deprovisioning of a licence nobody holds
    # is nobody's to apply.
    def license_named_by(event)
      MarketplaceLicense.find_by(license_arn: event.license_arn) ||
        (renewed_licence?(event) ? MarketplaceLicense.live.find_by(agreement_id: event.agreement_id) : nil)
    end

    def renewed_licence?(event) = event.detail_type == LICENSE_UPDATED && event.agreement_id.present?

    # The old licence being deprovisioned after a renewal, when the row has
    # moved to the new agreement but still carries the old ARN, must not end
    # the subscription that replaced it. A deprovisioning that names its
    # agreement says so itself. One that names none is asked about: the
    # agreement the row holds now is still live, or it is not.
    def superseded?(license, event)
      return false if event.license_arn.blank? || event.detail_type != LICENSE_DEPROVISIONED
      return event.agreement_id != license.agreement_id if event.agreement_id.present?
      return false if license.previous_agreement_id.blank?

      agreement = client.describe_agreement(agreement_id: license.agreement_id)
      raise Unread, "could not read agreement #{license.agreement_id} to tell whose licence this is" if agreement.nil?

      agreement.live?
    end

    # AWS fires `Purchase Agreement Created` for a renewal and a replacement
    # too, under a NEW agreement id with the old one in `previousAgreementId`.
    # Matched on the new id alone the event finds nothing, and an `Ended` for
    # the old agreement would stop a customer who has just renewed.
    def by_previous_agreement(event)
      previous = event.detail.dig("agreement", "previousAgreementId")
      MarketplaceLicense.find_by(agreement_id: previous) if previous.present?
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

    # The offer, the agreement the subscription is on now, and the licence AWS
    # issued for it: re-pointed, so an `Ended` for a superseded agreement
    # matches nothing and the meter names the licence AWS will accept usage
    # under. The agreement left behind is kept, because its licence can still
    # be deprovisioned after the move (#superseded?).
    def store(license, event)
      changes = {}
      offer = event.detail.dig("offer", "id")
      changes[:offer_identifier] = offer if offer.present? && offer != license.offer_identifier
      agreement = event.agreement_id
      if agreement.present? && agreement != license.agreement_id
        changes[:agreement_id] = agreement
        changes[:previous_agreement_id] = license.agreement_id
      end
      arn = event.license_arn
      changes[:license_arn] = arn if arn.present? && arn != license.license_arn

      license.update!(**changes) if changes.any?
    end

    # Not the metering deadline: AWS opens the final window on the
    # deprovisioning event, not here. The company loses access now and the
    # licence stays meterable until that event arrives; the usage goes first,
    # and the state moves either way.
    def close(license, event)
      meter_the_last_usage(license, event)
    ensure
      license.close! if license.may_close?
      block(license.company)
    end

    # The one hour AWS allows starts here, and the hourly schedule cannot serve
    # it: an hour reported at five past the next is already outside the window
    # for a licence deprovisioned after its first five minutes. The usage goes
    # before `finish!` makes the licence unmeterable.
    #
    # Sent again after `close`, deliberately: the two events arrive in one
    # drain, and whichever runs first catches the hour. AWS answers the repeat
    # `Success` with the id it issued the first time (measured against the real
    # listing; `DuplicateRecord` is for a differing quantity), so the customer
    # is billed once, and the stored receipt tells the repeat from a second
    # charge.
    #
    # Finished only once the usage has gone or the window has shut: `ended`
    # is unmeterable, so a licence finished around a call that never reached
    # AWS would be measured as nothing when the sweep came back for it. Until
    # then it is `ending`, which the retry can still meter.
    def deprovision(license, event)
      sent = meter_the_last_usage(license, event)
      license.finish! if license.may_finish?
      sent
    rescue StandardError
      license.close! if license.may_close?
      raise
    ensure
      block(license.company)
    end

    # AWS gives one hour from the event. A call that never reached AWS is
    # raised, which leaves the event unapplied for the next sweep; the state
    # still moves, through the `ensure` above. Once the window has shut no
    # retry can be accepted, so the attempt stops and says so.
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
