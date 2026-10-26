# frozen_string_literal: true

require "test_helper"

class Billing::MarketplaceEventsTest < ActiveSupport::TestCase
  OUR_PRODUCT_ID = "prod-ours"
  OUR_PRODUCT_CODE = "codeofours0000000000000"

  setup do
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
  # product, so every listing that account sells arrives here. Seen for real:
  # a stranger's subscription to "Easy Cloud Assurance" sat unapplied in our
  # table, and every sweep would have retried it for ever.
  test "another listing on the same seller account is not ours" do
    assert_nil @events.record(
      envelope(detail: { "agreement" => { "id" => "agmt-theirs" },
                         "product" => { "id" => "prod-someone-else", "title" => "Easy Cloud Assurance" } })
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
