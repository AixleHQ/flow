# frozen_string_literal: true

# Identity is (provider, subject), never email (AD-3). The unique index is the
# mechanical half of that rule — see AD-15.
class CreateUserIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :user_identities do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.references :identity_provider, null: false, foreign_key: true, index: true
      t.string :subject, null: false
      t.string :email
      t.boolean :email_verified, null: false, default: false
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :user_identities, %i[identity_provider_id subject], unique: true
  end
end
