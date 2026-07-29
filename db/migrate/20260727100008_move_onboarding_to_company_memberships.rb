# frozen_string_literal: true

# Onboarding becomes per-company. Joining a second company runs the whole flow
# again, because the answers are genuinely company-specific: the role differs,
# the agents chosen differ, and the agent credential MUST differ (billing).
#
# Every onboarding answer moves, including preferred_agent_language: keeping one
# field behind on users would mean two storage rules for one form.
class MoveOnboardingToCompanyMemberships < ActiveRecord::Migration[8.1]
  def up
    add_column :company_memberships, :onboarding_state, :string, null: false, default: "step1"
    add_column :company_memberships, :onboarding_completed_at, :datetime
    add_column :company_memberships, :position, :string
    add_column :company_memberships, :preferred_agent_language, :string, default: "en"
    add_column :company_memberships, :selected_agents, :text, array: true, default: []
    add_column :company_memberships, :default_agent_credential_id, :bigint
    add_index :company_memberships, :onboarding_state
    add_index :company_memberships, :default_agent_credential_id

    # Carry each user's single existing onboarding result onto their membership.
    execute <<~SQL
      UPDATE company_memberships cm
      SET onboarding_state = u.onboarding_state,
          onboarding_completed_at = u.onboarding_completed_at,
          position = u.position,
          preferred_agent_language = u.preferred_agent_language,
          selected_agents = u.selected_agents,
          default_agent_credential_id = u.default_agent_credential_id
      FROM users u
      WHERE u.id = cm.user_id
    SQL

    # The default credential must belong to the same company as the membership;
    # anything else was pointing across a tenant boundary.
    execute <<~SQL
      UPDATE company_memberships cm
      SET default_agent_credential_id = NULL
      WHERE default_agent_credential_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM agent_credentials ac
          WHERE ac.id = cm.default_agent_credential_id
            AND ac.company_id = cm.company_id
        )
    SQL

    add_foreign_key :company_memberships, :agent_credentials,
                    column: :default_agent_credential_id, on_delete: :nullify

    remove_column :users, :onboarding_state
    remove_column :users, :onboarding_completed_at
    remove_column :users, :position
    remove_column :users, :preferred_agent_language
    remove_column :users, :selected_agents
    remove_column :users, :default_agent_credential_id
  end

  def down
    add_column :users, :onboarding_state, :string, null: false, default: "step1"
    add_column :users, :onboarding_completed_at, :datetime
    add_column :users, :position, :string
    add_column :users, :preferred_agent_language, :string, default: "en"
    add_column :users, :selected_agents, :text, array: true, default: []
    add_column :users, :default_agent_credential_id, :bigint
    add_index :users, :onboarding_state
    add_index :users, :default_agent_credential_id

    # Collapse back to one answer per user: the oldest membership wins.
    execute <<~SQL
      UPDATE users u
      SET onboarding_state = cm.onboarding_state,
          onboarding_completed_at = cm.onboarding_completed_at,
          position = cm.position,
          preferred_agent_language = cm.preferred_agent_language,
          selected_agents = cm.selected_agents,
          default_agent_credential_id = cm.default_agent_credential_id
      FROM (
        SELECT DISTINCT ON (user_id) *
        FROM company_memberships
        ORDER BY user_id, accepted_at ASC NULLS FIRST, id ASC
      ) cm
      WHERE cm.user_id = u.id
    SQL

    remove_foreign_key :company_memberships, column: :default_agent_credential_id
    remove_column :company_memberships, :default_agent_credential_id
    remove_column :company_memberships, :selected_agents
    remove_column :company_memberships, :preferred_agent_language
    remove_column :company_memberships, :position
    remove_column :company_memberships, :onboarding_completed_at
    remove_column :company_memberships, :onboarding_state
  end
end
