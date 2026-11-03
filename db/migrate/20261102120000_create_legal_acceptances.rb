# frozen_string_literal: true

# One row each time somebody accepts a version of a legal document: the Terms of
# Use for themselves, or the Terms of Service on behalf of their company. Rows
# are never updated; a new version is a new row.
#
# A company's acceptance is the contract, so it outlives the person who clicked:
# permanently deleting them nullifies `user_id` and keeps the row.
class CreateLegalAcceptances < ActiveRecord::Migration[8.1]
  def change
    create_table :legal_acceptances do |t|
      t.references :user, index: false, foreign_key: { on_delete: :nullify }
      t.references :company, index: false, foreign_key: { on_delete: :cascade }
      t.string :document, null: false
      t.string :version, null: false
      t.datetime :accepted_at, null: false
      t.string :ip_address
      t.string :user_agent
      t.timestamps

      t.index %i[user_id document version]
      t.index %i[company_id document version]
    end
  end
end
