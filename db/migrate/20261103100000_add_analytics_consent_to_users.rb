# frozen_string_literal: true

# Null is "never asked", which is not the same as a refusal: the banner is shown
# for null and never for either answer.
class AddAnalyticsConsentToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :analytics_consent, :string
    add_column :users, :analytics_consent_at, :datetime
  end
end
