# frozen_string_literal: true

# Where we host, a company on the free trial — or stopped at its end — runs one
# worker until a card is added (Billing::Trial). Those that signed up before
# kept the number they typed, which they would have been billed for the moment
# they paid; this gives them the one a signup gets now.
#
# The capacity log is written with the limit: the meter reads a company's limit
# from that log, and a limit changed without it would be billed at the old
# number once the company pays. clock_timestamp(), not NOW(): NOW() is when the
# transaction began, which can sort before a change logged during it.
class HoldTrialingCompaniesToOneWorker < ActiveRecord::Migration[8.1]
  def up
    return unless Deployment.saas?

    execute(<<~SQL.squish)
      WITH targets AS (
        SELECT id FROM companies
        WHERE managed_by_aixle = FALSE
          AND (billing_state = 'trialing'
               OR (billing_state = 'blocked' AND COALESCE(billing_block_reason, 'allowance') = 'allowance'))
      ),
      updated AS (
        UPDATE session_concurrency_limits AS limits
        SET max_sessions = 1, updated_at = NOW()
        FROM targets
        WHERE limits.scope_type = 'Company' AND limits.scope_id = targets.id AND limits.max_sessions <> 1
        RETURNING limits.scope_id
      ),
      inserted AS (
        INSERT INTO session_concurrency_limits (scope_type, scope_id, company_id, max_sessions, created_at, updated_at)
        SELECT 'Company', targets.id, targets.id, 1, NOW(), NOW()
        FROM targets
        WHERE NOT EXISTS (
          SELECT 1 FROM session_concurrency_limits
          WHERE scope_type = 'Company' AND scope_id = targets.id
        )
        RETURNING scope_id
      )
      INSERT INTO company_capacity_changes (company_id, max_sessions, occurred_at, created_at)
      SELECT scope_id, 1, clock_timestamp(), clock_timestamp()
      FROM (SELECT scope_id FROM updated UNION ALL SELECT scope_id FROM inserted) AS changed
    SQL
  end

  # The numbers they had cannot be told from any set since.
  def down; end
end
