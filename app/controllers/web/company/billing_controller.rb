# frozen_string_literal: true

# The Billing tab of company settings: where the subscription stands, what this
# period has cost so far, the subscriptions that came before, and the controls
# that change it.
#
# Deliberately NOT under HostedBillingOnly, unlike the three controllers that
# *act* on billing: a workspace AWS Marketplace bills reads this page to see
# where its bill comes from and what has been reported towards it, and is
# offered no control that would be a second bill.
class Web::Company::BillingController < Web::Company::ApplicationController
  before_action :require_billing!

  def show
    price = Billing::CardPrice.new
    render inertia: "Company/Settings/BillingPage", props: {
      company: { name: current_company.name },
      billing: Billing::Overview.new(current_company, price: price).to_h,
      subscriptions: Billing::SubscriptionHistory.new(current_company, price: price).to_h,
      # The listing's page, where a workspace takes out an AWS Marketplace
      # subscription; absent where no listing is configured.
      listing_url: Billing::MarketplaceListing.listing_page_url,
      # Where Checkout sent the admin back from. Only these two values, so the
      # page never echoes an arbitrary query string.
      checkout_result: params[:billing].presence_in(%w[done cancelled]),
      # Shown to every admin: the decision moves who bills the workspace.
      marketplace_proposal: marketplace_proposal
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

  # Nil unless a card is actually paying: there is no final invoice otherwise.
  def final_invoice_minutes
    return nil if current_company.stripe_subscription_id.blank?

    billed = Billing::FinalUsage.new(current_company, until_time: Time.current).billed
    # The final invoice replays the last closed hour, in case the :05 run has
    # not delivered it yet. Where it has, Stripe takes the replay as the event
    # it already holds -- the same identifier -- so the hour is not owed again,
    # and counting it here overstated the invoice by an hour.
    sent = CapacityMeterReport.where(provider: Billing::Meter::Stripe.provider, period_start: billed.keys, state: "reported")
                              .pluck(:period_start).map(&:to_i)
    seconds = billed.reject { |hour, _| sent.include?(hour.to_i) }.values.sum
    (BigDecimal(seconds) / 60).round(1).to_f
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
