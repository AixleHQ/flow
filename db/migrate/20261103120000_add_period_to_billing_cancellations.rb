# frozen_string_literal: true

class AddPeriodToBillingCancellations < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_cancellations, :started_at, :datetime
    add_column :billing_cancellations, :period_started_at, :datetime
  end
end
