# frozen_string_literal: true

# The builder had no retry count, so every step it saved with On Failure = Retry
# kept max_retries 0 and never retried. Step now raises that to 1 on save; this
# does it for the rows already saved, and brings any count outside the 0..10
# Step accepts back inside it, so those steps stay editable.
class RetryStepsSetToRetryAtLeastOnce < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      UPDATE steps
      SET max_retries = CASE
            WHEN on_failure = 'retry' AND max_retries < 1 THEN 1
            ELSE LEAST(GREATEST(max_retries, 0), 10)
          END,
          updated_at = NOW()
      WHERE (on_failure = 'retry' AND max_retries < 1) OR max_retries NOT BETWEEN 0 AND 10
    SQL
  end

  # A step raised to one retry cannot be told from one an author set to one.
  def down; end
end
