# frozen_string_literal: true

# The Billing tab of company settings: where the subscription stands, what this
# period has cost so far, and the controls that change it.
#
# Deliberately NOT under HostedBillingOnly, unlike the three controllers that
# *act* on billing: a workspace AWS Marketplace bills reads this page to see
# where its bill comes from and what has been reported towards it, and is
# offered no control that would be a second bill.
class Web::Company::BillingController < Web::Company::ApplicationController
  before_action :require_billing!

  def show
    render inertia: "Company/Settings/BillingPage", props: {
      company: { name: current_company.name },
      billing: Billing::Overview.new(current_company).to_h,
      # Where Checkout sent the admin back from. Only these two values, so the
      # page never echoes an arbitrary query string.
      checkout_result: params[:billing].presence_in(%w[done cancelled]),
      # Shown to every admin: the decision moves who bills the workspace.
      marketplace_proposal: marketplace_proposal,
      # Deliberately NOT `marketplace`: that name is the shared prop the
      # stopped-workspace banner reads, and a page prop of the same name
      # shadows it.
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

  # Shown while AWS is the payer, and afterwards for as long as this calendar
  # month has minutes AWS was sent: a workspace that goes back to a card still
  # gets an AWS bill for them, and keyed on the payer alone the panel vanished
  # beside that charge.
  def marketplace_billing
    return nil unless current_company.billing_payer.aws_marketplace? || reported_minutes.positive?

    # The most recent, live or not: `marketplace_license` answers only for a
    # live one, and an ended subscription is exactly what this panel explains.
    license = current_company.marketplace_licenses.order(:id).last
    {
      aws_account_id: license&.customer_aws_account_id,
      subscribed_at: license&.subscribed_at,
      ended: license&.ended? || false,
      # False once a card has taken over: the panel is then a statement about
      # this month, not an offer to renew.
      bills_now: current_company.billing_payer.aws_marketplace?,
      reported_minutes: reported_minutes
    }
  end

  # Nil unless a card is actually paying: there is no final invoice otherwise.
  def final_invoice_minutes
    return nil if current_company.stripe_subscription_id.blank?

    seconds = Billing::FinalUsage.new(current_company, until_time: Time.current).billed.values.sum
    (BigDecimal(seconds) / 60).round(1).to_f
  end

  # What AWS has actually been sent this calendar month, from both paths that
  # send, keyed by AWS's receipt so the final meter's repeat counts once. Not
  # CompanyCapacityUsage, which is what the workspace was OFFERED: minutes the
  # card was billed for before a handover, minutes not yet sent, and
  # fractions. Billing::MarketplaceFinalMeter writes no ledger row, so its
  # receipts are read off the events.
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

  # Receipt -> minutes, floored the way the adapter floors what it sends.
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
      replaces_card: current_company.stripe_subscription_id.present?,
      # What accepting puts on the card's final invoice.
      final_invoice_minutes: final_invoice_minutes,
      # Accepting is refused until AWS confirms the agreement; declining is
      # offered either way.
      confirmed: license.active?,
      can_decide: current_membership&.admin? || false
    }
  end
end
