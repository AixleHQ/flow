# frozen_string_literal: true

class CreateCompanyMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :company_memberships do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :company, null: false, foreign_key: true
      t.string :role, null: false, default: "employee"
      t.string :state, null: false, default: "invited"
      t.bigint :invited_by_id
      t.datetime :invited_at
      t.datetime :accepted_at
      t.timestamps

      t.index %i[user_id company_id], unique: true
      t.index :state
      t.index :invited_by_id
    end

    add_foreign_key :company_memberships, :users, column: :invited_by_id
  end
end
