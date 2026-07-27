# frozen_string_literal: true

# Idempotency stamp for the invitation-reminder cron: set once a reminder is
# mailed, so a re-run or Temporal retry cannot mail the same invitee twice.
# Cleared on re-invite, which starts a fresh 7-day window.
class AddRemindedAtToCompanyMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :company_memberships, :reminded_at, :datetime
  end
end
