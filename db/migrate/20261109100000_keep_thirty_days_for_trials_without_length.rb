# frozen_string_literal: true

# The default trial goes from 30 days to 14 (TRIAL_DAYS). A company whose trial
# began before trials kept their length (AddTrialLength) has no trial_hours and
# follows the default, so the new one would cut its trial in half — or, once it
# has run past fourteen days, stop it at the next hourly check. It keeps the 30
# days it has been shown.
class KeepThirtyDaysForTrialsWithoutLength < ActiveRecord::Migration[8.1]
  def up
    return unless Deployment.saas?

    execute(<<~SQL.squish)
      UPDATE companies SET trial_hours = #{30 * 24}, updated_at = NOW()
      WHERE billing_state = 'trialing' AND trial_hours IS NULL
    SQL
  end

  # Clearing the length would also clear one an operator set after this ran.
  def down; end
end
