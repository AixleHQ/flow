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
      # same name shadows it -- which on 25 October made the banner read this
      # object, find no `status` on it, and announce a subscription that had
      # ended to a workspace whose subscription was running.
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

  def marketplace_billing
    return nil unless current_company.billing_payer.aws_marketplace?

    license = current_company.marketplace_license
    {
      aws_account_id: license&.customer_aws_account_id,
      subscribed_at: license&.subscribed_at,
      ended: license&.ended? || false,
      # What we have reported towards the AWS bill this calendar month, which is
      # the period AWS invoices on. Read from our own ledger rather than from
      # AWS: it is the same minutes, and it is the only figure available before
      # the invoice exists.
      reported_minutes: reported_minutes
    }
  end

  def reported_minutes
    seconds = CompanyCapacityUsage.where(company_id: current_company.id)
                                  .since(Time.current.utc.beginning_of_month)
                                  .sum(:quantity_seconds)
    (BigDecimal(seconds) / 60).round(1).to_f
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
      can_decide: current_membership&.admin? || false
    }
  end
end
