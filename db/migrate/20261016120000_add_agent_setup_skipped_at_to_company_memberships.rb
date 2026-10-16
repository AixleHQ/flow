# frozen_string_literal: true

class AddAgentSetupSkippedAtToCompanyMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :company_memberships, :agent_setup_skipped_at, :datetime
  end
end
