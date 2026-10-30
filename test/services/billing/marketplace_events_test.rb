# frozen_string_literal: true

require "test_helper"

class Billing::MarketplaceEventsTest < ActiveSupport::TestCase
  OUR_PRODUCT_ID = "prod-ours"
  OUR_PRODUCT_CODE = "codeofours0000000000000"

  setup do
    # Every envelope is dated 10:00 that day, and the sweep only looks
    # MarketplaceSubscriptionEvent::SWEPT_FOR back from now.
    travel_to Time.utc(2026, 10, 23, 10, 5)
    Settings.stubs(:aws_marketplace).returns(
      Hashie::Mash.new(saas: { product_id: OUR_PRODUCT_ID, product_code: OUR_PRODUCT_CODE })
    )
    @meter = Minitest::Mock.new
    @events = Billing::MarketplaceEvents.new(final_meter: @meter)
  end

  test "an event for another source is not ours and is not stored" do
    assert_nil @events.record(envelope(source: "aws.marketplacecatalog"))
    assert_equal 0, MarketplaceSubscriptionEvent.count
  end

  test "a type we do not handle is not stored" do
    assert_nil @events.record(envelope(detail_type: "Spend Threshold Reached"))
    assert_equal 0, MarketplaceSubscriptionEvent.count
  end

  # SQS promises at-least-once. The same event arriving twice is one event.
  test "a redelivered event is the same row" do
    first = @events.record(envelope)
    second = @events.record(envelope)

    assert_equal first.id, second.id
    assert_equal 1, MarketplaceSubscriptionEvent.count
  end

  test "an agreement event is stored under its agreement, a licence event under its ARN" do
    agreement = @events.record(envelope(detail_type: Billing::MarketplaceEvents::CREATED))
    licence = @events.record(
      envelope(id: "ev-2", detail_type: Billing::MarketplaceEvents::LICENSE_UPDATED,
               detail: { "license" => { "arn" => "arn:lic:1" } })
    )

    assert_equal "agmt-1", agreement.agreement_id
    assert_nil agreement.license_arn, "agreement events carry no licence ARN at all"
    assert_equal "arn:lic:1", licence.license_arn
  end

  # The race this table exists for: the agreement is created when the buyer
  # subscribes, the licence row when they reach the fulfilment page.
  test "an event with nothing to apply it to is kept, not dropped" do
    @events.record(envelope)

    assert_equal 0, @events.apply_pending
    assert_equal 1, MarketplaceSubscriptionEvent.unapplied.count
  end

  # The seller account sells more than this listing, and the rule that feeds
  # this table matches a source and a detail type rather than a product. So the
  # agreement traffic of every other listing lands here and never matches
  # anything -- and every sweep would reconsider all of it, for ever.
  test "an event nothing has claimed for a week stops being swept" do
    @events.record(envelope)
    MarketplaceSubscriptionEvent.sole.update!(occurred_at: 8.days.ago)
    create(:marketplace_license, agreement_id: "agmt-1")

    assert_equal 0, @events.apply_pending
    assert_not MarketplaceSubscriptionEvent.sole.applied?, "kept, as the evidence that this happens"
  end

  # Only the blind sweep gives up. A licence that appears late still replays the
  # events that named it, because there the match is certain rather than hoped
  # for.
  test "but a licence appearing late still replays its own" do
    @events.record(envelope)
    MarketplaceSubscriptionEvent.sole.update!(occurred_at: 8.days.ago)
    license = create(:marketplace_license, agreement_id: "agmt-1")

    assert @events.apply_for(license).active?
  end

  test "it applies the moment the licence appears" do
    @events.record(envelope)
    license = create(:marketplace_license, agreement_id: "agmt-1")

    assert_equal 1, @events.apply_pending
    assert license.reload.active?
    assert MarketplaceSubscriptionEvent.sole.applied?
  end

  test "a licence created later has its waiting events replayed for it" do
    @events.record(envelope)
    license = create(:marketplace_license, agreement_id: "agmt-1")

    assert @events.apply_for(license).active?
  end

  # Matched on its ARN alone: `agreement_id: nil` is every other listing's
  # licence event, and all of those used to be applied inside the buyer's
  # registration request.
  test "a licence that knows no agreement replays only the events naming its ARN" do
    @events.record(
      envelope(id: "ev-other", detail_type: Billing::MarketplaceEvents::LICENSE_UPDATED,
               detail: { "license" => { "arn" => "arn:lic:other" } })
    )
    license = create(:marketplace_license, license_arn: "arn:lic:1", agreement_id: nil)

    assert_empty MarketplaceSubscriptionEvent.awaiting(license)
    assert_equal 1, MarketplaceSubscriptionEvent.unapplied.count, "the other listing's event is still waiting"
  end

  test "an ended agreement closes the licence and stops the company" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, agreement_id: "agmt-1", company: company)
    @events.record(envelope(detail_type: Billing::MarketplaceEvents::ENDED))
    @meter.expect(:call, "nothing to send") { |_| true }

    @events.apply_pending

    assert license.reload.ending?, "ending, not ended: the final window has not opened yet"
    assert license.meterable?, "the last hour is still reportable"
    assert company.reload.billing_blocked?
  end

  # A call that never reached AWS has sent nothing, and the part-hour it was
  # carrying is the one the schedule can no longer reach. Swallowing it stopped
  # the workspace and lost the minutes: the next attempt found a stopped
  # workspace and measured zero.
  class FailingMeter
    def call(_license) = raise(Billing::MarketplaceSellerClient::Error, "cannot assume the seller role")
  end

  class RecordingMeter
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(license)
      @calls << license
      "sent=1:already=0:minutes=30"
    end
  end

  test "a final meter that could not reach AWS stops the workspace and is tried again" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, agreement_id: "agmt-1", company: company)
    Billing::MarketplaceEvents.new(final_meter: FailingMeter.new).record(envelope(detail_type: Billing::MarketplaceEvents::ENDED))

    travel_to Time.utc(2026, 10, 23, 10, 30) do
      Billing::MarketplaceEvents.new(final_meter: FailingMeter.new).apply_pending
    end

    event = MarketplaceSubscriptionEvent.sole
    assert_not event.applied?, "nothing was sent, so the sweep has to come back to it"
    assert_equal "cannot assume the seller role", event.failure
    assert company.reload.billing_blocked?, "the customer has cancelled; the workspace stops either way"
    assert license.reload.ending?

    meter = RecordingMeter.new
    travel_to Time.utc(2026, 10, 23, 10, 35) do
      Billing::MarketplaceEvents.new(final_meter: meter).apply_pending
    end

    assert_equal [ license ], meter.calls
    assert MarketplaceSubscriptionEvent.sole.applied?, "sent at last, inside the window AWS gave"
  end

  # Bounded by the window itself: once it has shut no record can be accepted,
  # so the attempt stops rather than being made every minute for ever.
  test "once the one-hour window has shut the event stops being retried" do
    create(:marketplace_license, :active, agreement_id: "agmt-1", company: create(:company))
    Billing::MarketplaceEvents.new(final_meter: FailingMeter.new).record(envelope(detail_type: Billing::MarketplaceEvents::ENDED))

    travel_to Time.utc(2026, 10, 23, 11, 30) do
      Billing::MarketplaceEvents.new(final_meter: FailingMeter.new).apply_pending
    end

    event = MarketplaceSubscriptionEvent.sole
    assert event.applied?
    assert_match(/window shut/, event.metered)
  end

  # The sharp one. AWS opens a one-hour window on this event and the hourly
  # schedule cannot serve it, so the usage goes before the state moves.
  test "a deprovisioned licence is metered before it is ended" do
    license = create(:marketplace_license, :active, agreement_id: "agmt-1", company: create(:company))
    @events.record(envelope(detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED))

    metered_while_meterable = nil
    @meter.expect(:call, "sent=1:minutes=27") { |arg| metered_while_meterable = arg.meterable?; arg == license }

    @events.apply_pending

    assert metered_while_meterable, "metered after finish! the usage would be refused"
    assert license.reload.ended?
    @meter.verify
  end

  # AWS fires Created for a renewal and a replacement as well as for a new
  # purchase, and a renewal carries a NEW agreement id naming the one it
  # supersedes. Matched only on the new id, it finds nothing, and the licence
  # goes on answering to an agreement that no longer exists.
  test "a renewal reaches the licence it renews and re-points it" do
    license = create(:marketplace_license, :active, agreement_id: "agmt-1", company: create(:company))
    @events.record(
      envelope(detail_type: Billing::MarketplaceEvents::CREATED,
               detail: { "agreement" => { "id" => "agmt-2", "intent" => "RENEW", "previousAgreementId" => "agmt-1" },
                         "product" => { "id" => OUR_PRODUCT_ID } })
    )

    assert_equal 1, @events.apply_pending
    assert_equal "agmt-2", license.reload.agreement_id
    assert_equal "agmt-1", license.previous_agreement_id, "kept: its licence can still be deprovisioned after the move"
    assert license.active?
  end

  # The other half: having moved, the licence no longer answers to the old
  # agreement, so its ending stops nobody.
  test "the ending of the agreement a renewal replaced does not stop the customer" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, agreement_id: "agmt-2", company: company)
    @events.record(envelope(detail_type: Billing::MarketplaceEvents::ENDED))

    assert_equal 0, @events.apply_pending, "it names agmt-1, which nothing holds any more"
    assert license.reload.active?
    assert company.reload.billing_active?
  end

  # Under Concurrent Agreements the new agreement comes with a licence of its
  # own. The row has to move to it, or the meter goes on naming a licence AWS
  # has finished with. A licence event is the first thing that carries both.
  test "the licence a renewal issued takes over the row of the one it replaced" do
    license = create(:marketplace_license, :active, license_arn: "arn:lic:1", agreement_id: "agmt-2",
                                                    previous_agreement_id: "agmt-1", company: create(:company))
    @events.record(
      envelope(detail_type: Billing::MarketplaceEvents::LICENSE_UPDATED,
               detail: { "license" => { "arn" => "arn:lic:2" }, "agreement" => { "id" => "agmt-2" },
                         "product" => { "code" => OUR_PRODUCT_CODE } })
    )

    assert_equal 1, @events.apply_pending
    assert_equal "arn:lic:2", license.reload.license_arn
    assert license.active?
    assert_equal 1, MarketplaceLicense.count, "the same subscription, not a second row"
  end

  # The old licence is deprovisioned after the move, and it still names the
  # row, which holds its ARN until the new licence is heard of. Ending the row
  # would stop a customer who has just renewed.
  test "the deprovisioning of the licence a renewal replaced ends nothing" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, license_arn: "arn:lic:1", agreement_id: "agmt-2",
                                                    previous_agreement_id: "agmt-1", company: company)
    @events.record(
      envelope(detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED,
               detail: { "license" => { "arn" => "arn:lic:1" }, "agreement" => { "id" => "agmt-1" },
                         "product" => { "code" => OUR_PRODUCT_CODE } })
    )

    assert_equal 1, @events.apply_pending, "applied, as the record that it was seen and set aside"
    assert license.reload.active?
    assert company.reload.billing_active?
    assert_match(/agmt-1, which agmt-2 replaced/, MarketplaceSubscriptionEvent.sole.metered)
  end

  # A deprovisioning that names no agreement could be either licence. AWS is
  # asked whether the agreement the row holds now is still live: if so, this
  # is the old licence going; if not, the subscription has ended.
  test "a deprovisioning that names no agreement is told apart by asking AWS" do
    client = FakeMarketplaceSellerClient.new
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, license_arn: "arn:lic:1", agreement_id: "agmt-2",
                                                    previous_agreement_id: "agmt-1", company: company)
    events = Billing::MarketplaceEvents.new(final_meter: RecordingMeter.new, client: client)
    events.record(
      envelope(detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED,
               detail: { "license" => { "arn" => "arn:lic:1" }, "product" => { "code" => OUR_PRODUCT_CODE } })
    )

    events.apply_pending

    assert_equal [ "agmt-2" ], client.described
    assert license.reload.active?, "the renewed agreement is live, so this was the old licence"
    assert company.reload.billing_active?

    client.agreement_status = "CANCELLED"
    events.record(
      envelope(id: "ev-2", detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED,
               detail: { "license" => { "arn" => "arn:lic:1" }, "product" => { "code" => OUR_PRODUCT_CODE } })
    )

    events.apply_pending

    assert license.reload.ended?, "nothing live to be the other licence of"
    assert company.reload.billing_blocked?
  end

  test "a deprovisioning AWS cannot be asked about is left for the next sweep" do
    client = FakeMarketplaceSellerClient.new
    client.agreement_status = nil
    license = create(:marketplace_license, :active, license_arn: "arn:lic:1", agreement_id: "agmt-2",
                                                    previous_agreement_id: "agmt-1", company: create(:company))
    events = Billing::MarketplaceEvents.new(final_meter: RecordingMeter.new, client: client)
    events.record(
      envelope(detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED,
               detail: { "license" => { "arn" => "arn:lic:1" }, "product" => { "code" => OUR_PRODUCT_CODE } })
    )

    assert_equal 0, events.apply_pending
    assert_not MarketplaceSubscriptionEvent.sole.applied?
    assert_match(/could not read agreement agmt-2/, MarketplaceSubscriptionEvent.sole.failure)
    assert license.reload.active?
  end

  # A licence never heard of, under an agreement nobody holds, is somebody
  # else's: the fallback by agreement is for the renewal case only -- and only
  # for the update that announces the new licence. A deprovisioning of a
  # licence nobody holds ends nothing, whatever agreement it names.
  test "a licence event under an unknown agreement matches nothing" do
    create(:marketplace_license, :active, license_arn: "arn:lic:1", agreement_id: "agmt-1")
    @events.record(
      envelope(detail_type: Billing::MarketplaceEvents::LICENSE_UPDATED,
               detail: { "license" => { "arn" => "arn:lic:9" }, "agreement" => { "id" => "agmt-9" },
                         "product" => { "code" => OUR_PRODUCT_CODE } })
    )

    assert_equal 0, @events.apply_pending
  end

  test "a deprovisioning of a licence nobody holds ends nothing, even under an agreement somebody does" do
    license = create(:marketplace_license, :active, license_arn: "arn:lic:1", agreement_id: "agmt-1",
                                                    company: create(:company))
    @events.record(
      envelope(detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED,
               detail: { "license" => { "arn" => "arn:lic:9" }, "agreement" => { "id" => "agmt-1" },
                         "product" => { "code" => OUR_PRODUCT_CODE } })
    )

    assert_equal 0, @events.apply_pending
    assert license.reload.active?
  end

  # Found by its ARN, the licence is the one going whatever agreement the event
  # names. A row that never learned its agreement used to read that name as
  # somebody else's and stay active, and unbilled, for ever.
  test "a deprovisioning finishes a licence that never learned its agreement" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, license_arn: "arn:lic:1", agreement_id: nil, company: company)
    @meter.expect(:call, "nothing to send", [ license ])
    @events.record(
      envelope(detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED,
               detail: { "license" => { "arn" => "arn:lic:1" }, "agreement" => { "id" => "agmt-1" },
                         "product" => { "code" => OUR_PRODUCT_CODE } })
    )

    assert_equal 1, @events.apply_pending
    assert license.reload.ended?
    assert company.reload.billing_blocked?
  end

  # `ended` is unmeterable. Finished around a call that never reached AWS, the
  # licence was measured as nothing when the sweep came back for it, and the
  # last hour was lost in exactly the window AWS gives for it.
  test "a deprovisioning whose final meter could not reach AWS is finished only once it has" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, agreement_id: "agmt-1", company: company)
    Billing::MarketplaceEvents.new(final_meter: FailingMeter.new)
                              .record(envelope(detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED))

    travel_to Time.utc(2026, 10, 23, 10, 30) do
      Billing::MarketplaceEvents.new(final_meter: FailingMeter.new).apply_pending
    end

    assert_not MarketplaceSubscriptionEvent.sole.applied?
    assert license.reload.ending?, "still meterable for the retry"
    assert company.reload.billing_blocked?, "the customer has cancelled; the workspace stops either way"

    meter = RecordingMeter.new
    travel_to Time.utc(2026, 10, 23, 10, 35) do
      Billing::MarketplaceEvents.new(final_meter: meter).apply_pending
    end

    assert_equal [ license ], meter.calls
    assert license.reload.ended?
    assert MarketplaceSubscriptionEvent.sole.applied?
  end

  # Out of order is normal, and the machine is what refuses it.
  test "a creation that arrives after an ending does not reopen the licence" do
    license = create(:marketplace_license, :active, agreement_id: "agmt-1")
    license.close!
    @events.record(envelope(detail_type: Billing::MarketplaceEvents::CREATED))

    @events.apply_pending

    assert license.reload.ending?
  end

  test "an amendment moves the offer identifier and nothing else" do
    license = create(:marketplace_license, :active, agreement_id: "agmt-1")
    @events.record(
      envelope(detail_type: Billing::MarketplaceEvents::AMENDED,
               detail: { "agreement" => { "id" => "agmt-1" }, "offer" => { "id" => "offer-new" } })
    )

    @events.apply_pending

    assert_equal "offer-new", license.reload.offer_identifier
    assert license.active?
  end

  test "a failure leaves the event for the next sweep, with the reason on it" do
    create(:marketplace_license, :active, agreement_id: "agmt-1", company: create(:company))
    @events.record(envelope(detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED))
    @meter.expect(:call, nil) { raise "AWS said no" }

    assert_equal 0, @events.apply_pending

    event = MarketplaceSubscriptionEvent.sole
    assert_not event.applied?
    assert_equal "AWS said no", event.failure
  end

  # The bug the first real subscription found: the workspace is created blocked
  # when the licence is still pending, and nothing lifted it. The customer paid
  # and the workspace never started.
  test "a confirmation starts the workspace that was waiting for it" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE,
                               billing_state: "blocked", billing_block_reason: "awaiting_subscription")
    create(:marketplace_license, agreement_id: "agmt-1", company: company)
    @events.record(envelope)

    @events.apply_pending

    assert company.reload.billing_active?
    assert_nil company.billing_block_reason
  end

  # Only that reason. A company stopped for an unpaid invoice or a spent
  # allowance is not started by an agreement message.
  test "a confirmation does not start a workspace blocked for another reason" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE,
                               billing_state: "blocked", billing_block_reason: "payment_failed")
    create(:marketplace_license, agreement_id: "agmt-1", company: company)
    @events.record(envelope)

    @events.apply_pending

    assert company.reload.billing_blocked?
    assert_equal "payment_failed", company.billing_block_reason
  end

  # The failure the first cancellation found. Both events arrive seconds apart
  # and apply in one pass, so by the time the deprovisioning is handled the
  # company is already stopped -- and a stopped company is measured as having
  # offered nothing for the whole hour, including the part it was running.
  test "the last usage is metered while the company can still be measured" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, agreement_id: "agmt-1", company: company)
    @events.record(envelope(detail_type: Billing::MarketplaceEvents::ENDED))

    measured_while_billable = nil
    @meter.expect(:call, "sent=1:minutes=27") { |arg| measured_while_billable = arg.company.billing_active?; arg == license }

    @events.apply_pending

    assert measured_while_billable, "metered after the block, CapacityWindow finds nothing"
    @meter.verify
  end

  # Both events meter. The second copy is answered DuplicateRecord, which costs
  # nothing; a missed first copy costs the hour.
  test "both halves of a cancellation meter" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :active, agreement_id: "agmt-1", company: company)
    @events.record(envelope(id: "ev-end", detail_type: Billing::MarketplaceEvents::ENDED))
    @events.record(envelope(id: "ev-dep", detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED))

    metered = 0
    2.times { @meter.expect(:call, "nothing to send") { |_| metered += 1 } }

    @events.apply_pending

    assert_equal 2, metered
    @meter.verify
  end

  # The rule in the seller account matches a source and a detail type, not a
  # product, so every listing that account sells arrives here -- including
  # strangers' subscriptions to other vendors' products, which sit unapplied and
  # which every sweep would otherwise retry for ever.
  test "another listing on the same seller account is not ours" do
    assert_nil @events.record(
      envelope(detail: { "agreement" => { "id" => "agmt-theirs" },
                         "product" => { "id" => "prod-someone-else", "title" => "Another Vendor's Product" } })
    )
    assert_equal 0, MarketplaceSubscriptionEvent.count
  end

  # Licence events name the product by code, agreement events by id. Either
  # spelling of ours is ours.
  test "the product is recognised by code as well as by id" do
    event = @events.record(
      envelope(detail_type: Billing::MarketplaceEvents::LICENSE_UPDATED,
               detail: { "license" => { "arn" => "arn:lic:1" },
                         "product" => { "code" => OUR_PRODUCT_CODE } })
    )

    assert event
  end

  # Better a row nobody matches than a dropped one that was ours.
  test "an event naming no product at all is kept" do
    assert @events.record(envelope(detail: { "agreement" => { "id" => "agmt-1" } }))
  end

  # The hourly meter leaves a ledger row; this path left nothing, so whether a
  # cancelling customer's last hour was billed could only be read off their own
  # invoice hours later.
  test "what the final meter sent is recorded against the event that ran it" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :active, agreement_id: "agmt-1", company: company)
    @events.record(envelope(detail_type: Billing::MarketplaceEvents::LICENSE_DEPROVISIONED))
    @meter.expect(:call, "sent=1:already=0:minutes=27") { |_| true }

    @events.apply_pending

    assert_equal "sent=1:already=0:minutes=27", MarketplaceSubscriptionEvent.sole.metered
  end

  test "an event that meters nothing records nothing" do
    create(:marketplace_license, agreement_id: "agmt-1", company: create(:company))
    @events.record(envelope)

    @events.apply_pending

    assert_nil MarketplaceSubscriptionEvent.sole.metered
  end

  private

  def envelope(id: "ev-1", source: Billing::MarketplaceEvents::SOURCE,
               detail_type: Billing::MarketplaceEvents::CREATED, detail: nil)
    {
      "id" => id,
      "source" => source,
      "detail-type" => detail_type,
      "time" => "2026-10-23T10:00:00Z",
      "detail" => detail || {
        "agreement" => { "id" => "agmt-1" },
        "product" => { "id" => OUR_PRODUCT_ID }
      }
    }
  end
end
