# frozen_string_literal: true

# oauth-unification §4.5: N-consecutive-failure escalation. A single failed
# refresh keeps the credential usable (the sweep retries next tick); only after
# MAX_REFRESH_FAILURES consecutive failures does it flip to status:error (badge +
# reconnect + notification). Any successful refresh resets the counter to 0.
class AddRefreshFailureCountToOauthCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_credentials, :refresh_failure_count, :integer, null: false, default: 0
  end
end
