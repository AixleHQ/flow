# frozen_string_literal: true

# The Billing tab of company settings: where the subscription stands, what this
# period has cost so far, and the controls that change it.
class Web::Company::BillingController < Web::Company::ApplicationController
  include HostedBillingOnly

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
      marketplace_proposal: marketplace_proposal
    }
  end

  private

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
      can_decide: current_membership&.admin? || false
    }
  end
end
