# frozen_string_literal: true

# A row per signed-in browser, so a sign-in can be ended from the server: by the
# person ("sign out everywhere"), by an administrator, by an account being
# suspended or deleted, or by the idle and absolute timeouts. The session cookie
# now carries this row's id next to the user id it always carried.
class CreateUserSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :impersonator, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :ip_address
      t.string :user_agent
      t.datetime :last_seen_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :user_sessions, %i[user_id revoked_at]
  end
end
