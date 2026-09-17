# frozen_string_literal: true

# The User scope governed sessions launched outside a project — in practice agent
# logins. Those are exempt from admission now (SessionAdmissionService#enqueue!
# returns nil for a session with no project), so the rows decide nothing, and
# SessionConcurrencyLimit no longer accepts the scope: left in place they would be
# invalid records that any later save of the table trips over.
#
# Data only, so nothing changes in the schema but its version.
class DropUserSessionConcurrencyLimits < ActiveRecord::Migration[8.1]
  def up
    deleted = execute("DELETE FROM session_concurrency_limits WHERE scope_type = 'User'").cmd_tuples
    say "Removed #{deleted} user-scoped session concurrency limit(s)" if deleted.positive?
  end

  # Irreversible by nature: the values are gone and the scope that gave them
  # meaning no longer exists. Declared so a rollback of the batch does not fail.
  def down
    say "User-scoped session concurrency limits are not restored; the scope no longer exists"
  end
end
