# frozen_string_literal: true

# A proof means nothing without its session, and sessions are only ever removed
# in bulk, with no callbacks: User's `dependent: :delete_all` (permanent user
# deletion), the ended-session sweep in UserSession.start! (every sign-in), and
# the users -> user_sessions ON DELETE CASCADE. Behind a plain foreign key the
# first proof under any of those sessions refuses the DELETE, so the proofs go
# with the session in the database.
class CascadeUserSessionProofsWithTheirSession < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :user_session_proofs, :user_sessions
    add_foreign_key :user_session_proofs, :user_sessions, on_delete: :cascade
  end

  def down
    remove_foreign_key :user_session_proofs, :user_sessions
    add_foreign_key :user_session_proofs, :user_sessions
  end
end
