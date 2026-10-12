# frozen_string_literal: true

require "test_helper"

class Billing::SettleCancellationJobTest < ActiveJob::TestCase
  setup do
    @client = FakeStripeClient.new
    Billing::StripeClient.stubs(:new).returns(@client)
    @company = create(:company, :subscribed, billing_state: "blocked", billing_block_reason: "canceled")
    @client.add_subscription(id: @company.stripe_subscription_id)
    @client.cancel_subscription(subscription_id: @company.stripe_subscription_id, reason: nil, comment: nil)
    @invoice_id = "in_final_#{@company.stripe_subscription_id}"
    @cancellation = create(:billing_cancellation, company: @company, settlement_state: "settling",
                                                  final_invoice_id: @invoice_id,
                                                  final_usage: { Time.utc(2026, 10, 12, 14).iso8601 => 600 })
  end

  test "it settles the cancellation" do
    perform_enqueued_jobs { Billing::SettleCancellationJob.perform_later(@cancellation.id) }

    assert_equal "settled", @cancellation.reload.settlement_state
  end

  test "out of attempts, the invoice goes back to Stripe and the failure is reported" do
    @client.counting = false

    assert_error_reported(Billing::CancellationSettlement::NotYetCounted) do
      perform_enqueued_jobs { Billing::SettleCancellationJob.perform_later(@cancellation.id) }
    end

    assert_equal "failed", @cancellation.reload.settlement_state
    assert @client.invoices.fetch(@invoice_id)[:auto_advance]
  end
end
