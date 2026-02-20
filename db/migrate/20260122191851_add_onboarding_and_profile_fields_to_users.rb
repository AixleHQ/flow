class AddOnboardingAndProfileFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :onboarding_completed_at, :datetime
    add_column :users, :position, :string
    add_column :users, :preferred_agent_language, :string, default: "en"
  end
end
