# frozen_string_literal: true

class AddBillingProviderSinceToCompanies < ActiveRecord::Migration[8.1]
  # When the company's current payer took over.
  #
  # An hour is measured after it closes, against the company as it is then, so
  # a company that changed payer at 18:36 had the whole of 18:00 attributed to
  # whoever bills it at 19:05. The time before the switch was the old payer's:
  # free, if the workspace was trialing, and already on the old payer's final
  # invoice if it was paying. Either way the new payer was sent it too.
  #
  # Nil means no change has been recorded, which is every company that existed
  # before this shipped and every one that has only ever had one payer. Those
  # are measured exactly as before.
  def change
    add_column :companies, :billing_provider_since, :datetime
  end
end
