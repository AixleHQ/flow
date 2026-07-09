# frozen_string_literal: true

# oauth-unification §7 security quick win: drop the dead plaintext Google token
# columns. They were written on every Google OAuth login but never read anywhere,
# so they were pure cleartext-secret liability. Google OAuth here is login-only.
class DropDeadGoogleTokenColumns < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :google_token, :string
    remove_column :users, :google_refresh_token, :string
  end
end
