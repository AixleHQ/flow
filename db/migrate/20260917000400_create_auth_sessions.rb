# frozen_string_literal: true

# Server-side login sessions (AD-6). Named AuthSession rather than Session
# because "session" already means an agent terminal session in this codebase
# (TerminalSession, SessionLog) — see the spine's AD-6 amendment note.
class CreateAuthSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :auth_sessions do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :token_digest, null: false
      t.string :ip
      t.string :user_agent
      t.datetime :last_seen_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :auth_sessions, :token_digest, unique: true
    add_index :auth_sessions, :revoked_at, where: "revoked_at IS NULL"
  end
end
