# frozen_string_literal: true

class AddOnboardingCompletedAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :onboarding_completed_at, :datetime unless column_exists?(:users, :onboarding_completed_at)
  end
end
