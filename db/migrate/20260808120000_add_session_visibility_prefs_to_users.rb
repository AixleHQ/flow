# frozen_string_literal: true

# Per-user session sharing preferences, edited from the profile page.
#
# They govern what OTHER people (project members, company admins) may open —
# never what the owner sees. Defaults keep the historical behaviour for finished
# sessions (project members could already open every session in their project)
# while closing the live terminal, which handed anyone in the project an
# interactive shell in someone else's container.
class AddSessionVisibilityPrefsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :share_active_sessions, :boolean, default: false, null: false
    add_column :users, :share_completed_sessions, :boolean, default: true, null: false
  end
end
