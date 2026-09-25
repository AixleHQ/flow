# frozen_string_literal: true

# Single-use, short-lived sign-in links (CAP-4).
#
# An explicit table rather than `generates_token_for`: an invitation token is
# 7-day and reusable-until-consumed, and a LOGIN link must be neither. Storing
# the digest with its own `consumed_at` makes single use a database fact that
# one transaction can enforce, instead of an emergent property of a signed blob.
class CreateMagicLinkTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :magic_link_tokens do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.string :requested_ip

      t.timestamps
    end

    add_index :magic_link_tokens, :token_digest, unique: true
    add_index :magic_link_tokens, :expires_at
  end
end
