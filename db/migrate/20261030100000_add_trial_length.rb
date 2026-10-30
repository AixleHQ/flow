# frozen_string_literal: true

# A trial becomes a number of days (TRIAL_DAYS) instead of TRIAL_QUEUE_HOURS of
# capacity. The company keeps the length of the trial it is on, in worker-hours,
# which is what the meter counts: a new default changes no trial under way, and
# an operator who moves a company's last day sets it here.
class AddTrialLength < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :trial_hours, :integer
  end
end
