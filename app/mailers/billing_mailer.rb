# frozen_string_literal: true

class BillingMailer < ApplicationMailer
  # To every admin of the company, the one who cancelled included.
  def subscription_cancelled(cancellation, recipient)
    @company = cancellation.company
    @actor = cancellation.user
    @recipient = recipient
    @ended_on = cancellation.cancels_at.strftime("%B %-d, %Y")
    @billing_url = company_settings_billing_url

    mail(
      to: recipient.email,
      subject: "The Aixle Flow subscription for #{@company.branded_name} is cancelled"
    )
  end

  # To every admin, once: the card on file declined the cancelled subscription's
  # final invoice. Paying goes through the Billing tab, so the link is ours and
  # not Stripe's.
  def final_invoice_unpaid(company, recipient)
    @company = company
    @billing_url = company_settings_billing_url

    mail(
      to: recipient.email,
      subject: "The final Aixle Flow invoice for #{@company.branded_name} is unpaid"
    )
  end
end
