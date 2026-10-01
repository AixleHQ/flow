# frozen_string_literal: true

class CreateTrackerAccounts < ActiveRecord::Migration[8.1]
  def change
    # Every tracker account id Aixle keeps (event actors, assignees, the
    # connection's own identity), so it can be reported to Atlassian's Personal
    # Data Reporting API and erased when the account is closed. Ids only.
    create_table :tracker_accounts do |t|
      t.string :provider, null: false
      t.string :account_id, null: false
      t.string :status, null: false, default: "active"
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :reported_at
      t.datetime :closed_at
      t.timestamps
    end
    add_index :tracker_accounts, %i[provider account_id], unique: true
    add_index :tracker_accounts, %i[provider status reported_at]
  end
end
