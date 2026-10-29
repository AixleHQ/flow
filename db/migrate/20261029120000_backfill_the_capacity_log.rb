# frozen_string_literal: true

class BackfillTheCapacityLog < ActiveRecord::Migration[8.1]
  # The capacity log was never backfilled the way the billing-state log was, so
  # a company whose limit predates it is read from its live row -- until its
  # first change, which puts it in the log without an opening entry. The hour
  # of that change opened with the company absent, and the part before the
  # change was billed to nobody.
  #
  # One row per company, stating what it has now, from now: its limit, or none,
  # which the window answers with the ceiling exactly as the live row did.
  def up
    execute(<<~SQL.squish)
      INSERT INTO company_capacity_changes (company_id, max_sessions, occurred_at, created_at)
      SELECT c.id, l.max_sessions, NOW(), NOW()
        FROM companies c
        LEFT JOIN session_concurrency_limits l ON l.scope_type = 'Company' AND l.scope_id = c.id
       WHERE NOT EXISTS (
             SELECT 1 FROM company_capacity_changes g WHERE g.company_id = c.id
       )
    SQL
  end

  # Irreversible on purpose: there is no telling a backfilled row from one a
  # real change wrote, and deleting the wrong one puts the gap back.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
