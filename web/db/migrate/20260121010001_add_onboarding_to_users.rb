# frozen_string_literal: true

class AddOnboardingToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :onboarding_completed_at, :datetime
    add_column :users, :selected_agents, :jsonb, default: [], null: false
  end
end
