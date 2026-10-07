# frozen_string_literal: true

class BillingMailer < ApplicationMailer
  # To every admin of the company, the one who cancelled included.
  def cancellation_scheduled(cancellation, recipient)
    @company = cancellation.company
    @actor = cancellation.user
    @recipient = recipient
    @ends_on = cancellation.cancels_at.strftime("%B %-d, %Y")
    @billing_url = company_settings_billing_url

    mail(
      to: recipient.email,
      subject: "The Aixle Flow subscription for #{@company.branded_name} ends on #{@ends_on}"
    )
  end
end
