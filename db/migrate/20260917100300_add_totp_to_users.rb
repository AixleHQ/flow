# frozen_string_literal: true

# TOTP as a STEP-UP method (CAP-4): it never starts a session, it only adds a
# proof to one that already exists. That keeps it inside the OR-shaped proof
# model — a company that requires TOTP is requiring a proof its members can only
# obtain after authenticating some other way — without needing the conjunctive
# ("SAML *and* TOTP") semantics the spine deliberately defers.
class AddTotpToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :encrypted_totp_secret, :text
    add_column :users, :totp_confirmed_at, :datetime
  end
end
