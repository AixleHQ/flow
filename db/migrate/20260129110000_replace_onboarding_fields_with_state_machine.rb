# frozen_string_literal: true

class ReplaceOnboardingFieldsWithStateMachine < ActiveRecord::Migration[8.0]
  def up
    # Add selected_agents column (was in a separate migration, now consolidated)
    unless column_exists?(:users, :selected_agents)
      add_column :users, :selected_agents, :text, array: true, default: []
    end

    # Add onboarding_state column
    add_column :users, :onboarding_state, :string, default: "step1", null: false

    # Migrate existing data from onboarding_completed_at (if exists)
    if column_exists?(:users, :onboarding_completed_at)
      execute <<-SQL
        UPDATE users
        SET onboarding_state = CASE
          WHEN onboarding_completed_at IS NOT NULL THEN 'completed'
          ELSE 'step1'
        END
      SQL
      # Keep onboarding_completed_at column - it stores the timestamp
    else
      # Add onboarding_completed_at if missing
      add_column :users, :onboarding_completed_at, :datetime
    end

    # Remove onboarding_step if exists (from previous migration)
    if column_exists?(:users, :onboarding_step)
      remove_column :users, :onboarding_step
    end

    # Add index for faster lookups
    add_index :users, :onboarding_state
  end

  def down
    # Migrate data back (set timestamp for completed users if missing)
    execute <<-SQL
      UPDATE users
      SET onboarding_completed_at = CASE
        WHEN onboarding_state = 'completed' AND onboarding_completed_at IS NULL THEN NOW()
        ELSE onboarding_completed_at
      END
    SQL

    # Remove index and column
    remove_index :users, :onboarding_state
    remove_column :users, :onboarding_state
    remove_column :users, :selected_agents
  end
end
