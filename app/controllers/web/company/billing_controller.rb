# frozen_string_literal: true

# The Billing tab of company settings: where the subscription stands, what this
# period has cost so far, and the controls that change it.
#
# Deliberately NOT under HostedBillingOnly, which the three controllers that
# *act* on billing still are. A workspace AWS Marketplace bills has nothing to
# manage here, and turning it away made its billing look missing rather than
# managed somewhere else. It reads this page instead, which says where its bill
# comes from and what we have reported towards it, and offers no control that
# would be a second bill for the same capacity.
class Web::Company::BillingController < Web::Company::ApplicationController
  before_action :require_billing!

  def show
    render inertia: "Company/Settings/BillingPage", props: {
      company: { name: current_company.name },
      billing: Billing::Overview.new(current_company).to_h,
      # Where Checkout sent the admin back from. Only these two values, so the
      # page never echoes an arbitrary query string.
      checkout_result: params[:billing].presence_in(%w[done cancelled]),
      # A subscription bought in AWS asking to be applied here. Shown to every
      # admin because the decision moves who bills the workspace, and the one
      # who happens to open this page is not necessarily the one who should
      # answer.
      marketplace_proposal: marketplace_proposal,
      # Set once AWS bills this workspace, which is what the page shows instead
      # of controls. Deliberately NOT `marketplace`: that name is taken by the
      # shared prop the stopped-workspace banner reads, and a page prop of the
      # same name shadows it: the banner then reads this object, finds no
      # `status` on it, and announces an ended subscription to a workspace whose
      # subscription is running.
      marketplace_billing: marketplace_billing
    }
  end

  private

  # What HostedBillingOnly refuses, minus the Marketplace case this page now
  # answers for.
  def require_billing!
    unless Deployment.saas?
      return redirect_to company_settings_path, alert: "Billing is not available on this installation."
    end
    return unless current_company.managed_by_aixle?

    redirect_to company_settings_path, alert: "This workspace is managed by Aixle and is not billed."
  end

  # Shown while AWS is the payer, and also after it has stopped being one if
  # AWS has already been sent minutes this calendar month.
  #
  # The second half is the part a customer feels. A workspace that leaves AWS
  # for a card still gets an AWS bill at the end of the month for what it ran
  # there -- and keyed on the payer alone this panel vanished the moment the
  # card arrived, leaving the product saying "0 worker-minutes this period"
  # beside a charge it never mentions. The same mistake the Billing tab made
  # from the other side, when it hid itself from a workspace AWS billed.
  def marketplace_billing
    return nil unless current_company.billing_payer.aws_marketplace? || reported_minutes.positive?

    # The most recent, live or not: a workspace whose subscription has ended is
    # exactly the one that needs this panel, and `marketplace_license` answers
    # only for the live one.
    license = current_company.marketplace_licenses.order(:id).last
    {
      aws_account_id: license&.customer_aws_account_id,
      subscribed_at: license&.subscribed_at,
      ended: license&.ended? || false,
      # Whether AWS is the payer NOW. False on a workspace that has gone back
      # to a card: the panel is then a statement about this month, not an
      # offer to renew.
      bills_now: current_company.billing_payer.aws_marketplace?,
      # What we have reported towards the AWS bill this calendar month, which is
      # the period AWS invoices on. The only figure available before the invoice
      # exists, so it has to be the one AWS was actually sent — see below.
      reported_minutes: reported_minutes
    }
  end

  # Nil unless a card is actually paying: there is no final invoice otherwise.
  def final_invoice_minutes
    return nil if current_company.stripe_subscription_id.blank?

    seconds = Billing::FinalUsage.new(current_company, until_time: Time.current).billed.values.sum
    (BigDecimal(seconds) / 60).round(1).to_f
  end

  # What AWS has actually been sent this calendar month, from BOTH paths that
  # send, counted by AWS's own receipt so nothing lands twice.
  #
  # Not CompanyCapacityUsage, which is what the workspace was OFFERED: that
  # holds minutes the card was billed for before a mid-month handover, minutes
  # measured but not yet sent, and fractions where a record carries whole
  # numbers.
  #
  # Two paths, because the hourly meter is not the only one. A cancellation
  # sends the last part-hour through Billing::MarketplaceFinalMeter, which
  # writes no ledger row -- so a figure built from ledger rows alone misses
  # exactly the minutes a cancelling customer is most likely to check.
  #
  # Keyed by receipt, which also settles the repeat: the two cancellation
  # events send the same record and AWS answers both with the id it issued
  # first, so the id appears twice and the minutes count once.
  def reported_minutes
    @reported_minutes ||= begin
      licenses = current_company.marketplace_licenses.pluck(:id, :license_arn)
      if licenses.empty?
        0.0
      else
        (hourly_receipts(licenses.map(&:last)).merge(final_meter_receipts(licenses.map(&:first))))
          .values.sum.to_f
      end
    end
  end

  # Receipt -> minutes, from the hourly ledger. The row carries one receipt per
  # licence and the company's seconds in its breakdown; the record AWS was sent
  # carries whole minutes, so this floors the same way the adapter does.
  def hourly_receipts(arns)
    CapacityMeterReport
      .where(provider: Billing::Meter::AwsMarketplaceSaas.provider)
      .where(period_start: Time.current.utc.beginning_of_month..)
      .pluck(:breakdown, :receipts)
      .each_with_object({}) do |(breakdown, receipts), map|
        arns.each do |arn|
          id = receipts[arn]
          next if id.blank?

          map[id] = (BigDecimal(breakdown[current_company.id.to_s].to_s.presence || "0") / 60).floor
        end
      end
  end

  def final_meter_receipts(license_ids)
    MarketplaceSubscriptionEvent
      .where(marketplace_license_id: license_ids)
      .where("occurred_at >= ?", Time.current.utc.beginning_of_month)
      .pluck(:metered_receipts)
      .each_with_object({}) { |receipts, map| map.merge!(receipts.to_h) }
  end

  def marketplace_proposal
    license = Billing::MarketplaceLicenseProposal.pending_for(current_company)
    return nil if license.nil?

    {
      asked_by: license.proposed_by_email,
      aws_account_id: license.customer_aws_account_id,
      asked_at: license.proposed_at,
      # What accepting would stop. The admin should not have to work out that
      # the card goes away from the fact that two things cannot both bill.
      replaces_card: current_company.stripe_subscription_id.present?,
      # And what that costs: the capacity the card has not been billed for yet,
      # which accepting puts on its final invoice. An ordinary cancellation
      # shows this on a screen of its own; deciding this one blind was the
      # difference.
      final_invoice_minutes: final_invoice_minutes,
      # Accepting is refused until AWS confirms the agreement, so the card says
      # so rather than letting an administrator press a button that cannot
      # work. Declining is offered either way.
      confirmed: license.active?,
      can_decide: current_membership&.admin? || false
    }
  end
end
