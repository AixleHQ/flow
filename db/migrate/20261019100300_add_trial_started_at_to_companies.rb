# frozen_string_literal: true

# When the free allowance a company is spending began. Null is the allowance it
# was given at sign-up, counted over everything it ever used; an operator who
# restarts a company by hand starts a new one, counted from then.
class AddTrialStartedAtToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :trial_started_at, :datetime
  end
end
