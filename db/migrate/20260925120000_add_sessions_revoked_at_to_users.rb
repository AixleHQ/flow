# frozen_string_literal: true

class AddSessionsRevokedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :sessions_revoked_at, :datetime
  end
end
