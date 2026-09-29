# frozen_string_literal: true

# Keeps the sessions that are live at the cutover signed in.
#
# The policy gate asks which method backs a session (AD-5/AD-6), and answers it
# from user_session_proofs. Sessions created before that table existed have no
# proof, so every one of them would be sent to step-up on the next request —
# not because any company's policy changed, but because `user_sessions` records
# no method and the question is new.
#
# Where the answer is unambiguous it is recovered rather than asked for: a user
# holding exactly one identity provider authenticated through that one, since
# there was nothing else to authenticate through. A user holding several is
# skipped — guessing which of them backed the session would be inventing the
# proof, and step-up is the correct outcome there.
class ProveLiveSessionsAtCutover < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      WITH sole_provider AS (
        SELECT user_id, MIN(identity_provider_id) AS identity_provider_id
        FROM user_identities
        GROUP BY user_id
        HAVING COUNT(DISTINCT identity_provider_id) = 1
      )
      INSERT INTO user_session_proofs
        (user_session_id, identity_provider_id, proved_at, created_at, updated_at)
      SELECT user_sessions.id, sole_provider.identity_provider_id,
             user_sessions.created_at, NOW(), NOW()
      FROM user_sessions
      JOIN sole_provider ON sole_provider.user_id = user_sessions.user_id
      WHERE user_sessions.revoked_at IS NULL
      ON CONFLICT (user_session_id, identity_provider_id) DO NOTHING
    SQL
  end

  # Deliberately a no-op. The rows are indistinguishable from proofs recorded by
  # a real sign-in, and deleting them would sign out everyone this migration was
  # written to keep signed in.
  def down; end
end
