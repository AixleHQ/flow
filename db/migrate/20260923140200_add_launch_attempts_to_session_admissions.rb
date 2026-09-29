# frozen_string_literal: true

# How many times the launch relay has claimed this admission. Past
# SessionLaunchRelay::MAX_LAUNCH_ATTEMPTS a launch that cannot start is failed,
# which frees its slot, instead of being retried while holding it.
class AddLaunchAttemptsToSessionAdmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :session_admissions, :launch_attempts, :integer, null: false, default: 0
  end
end
