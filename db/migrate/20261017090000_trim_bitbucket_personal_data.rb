# frozen_string_literal: true

# Atlassian account ids were kept longer than anything needed them: the
# installer's on the installation, and the administrator's on a spent pairing.
# A pairing is now deleted once it is confirmed, and expired ones are swept, so
# an account id lives only while its ten-minute link does.
class TrimBitbucketPersonalData < ActiveRecord::Migration[8.1]
  def change
    remove_column :bitbucket_installations, :installer_account_id, :string

    remove_foreign_key :bitbucket_pairings, :projects
    remove_foreign_key :bitbucket_pairings, :users, column: :consumed_by_id
    remove_column :bitbucket_pairings, :consumed_at, :datetime
    remove_column :bitbucket_pairings, :consumed_by_id, :bigint
    remove_column :bitbucket_pairings, :project_id, :bigint
    add_index :bitbucket_pairings, :expires_at
  end
end
