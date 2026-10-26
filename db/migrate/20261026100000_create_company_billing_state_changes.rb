# frozen_string_literal: true

class CreateCompanyBillingStateChanges < ActiveRecord::Migration[8.1]
  # What a company's billing state was, over time.
  #
  # The hour is measured after it closes, against the company as it is then, and
  # that snapshot has now produced the same overcharge three times: a workspace
  # created mid-hour, a workspace that changed payer mid-hour, and a workspace
  # unblocked mid-hour, each billed for the whole of it. The first two were
  # closed with a timestamp apiece. This is the third, and a third timestamp
  # would close the symptom and leave the mechanism, so it gets what capacity
  # already has -- a log, read for the hour being measured rather than for now.
  def change
    create_table :company_billing_state_changes do |t|
      t.references :company, null: false, foreign_key: true
      t.string :billing_state, null: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :company_billing_state_changes, %i[company_id occurred_at],
              name: "index_billing_state_changes_on_company_and_time"
    add_index :company_billing_state_changes, :occurred_at
  end
end
