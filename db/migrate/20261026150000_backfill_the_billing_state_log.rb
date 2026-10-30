# frozen_string_literal: true

class BackfillTheBillingStateLog < ActiveRecord::Migration[8.1]
  # The log starts empty, and a company absent from it is read from its live row
  # instead -- which is the very snapshot the log exists to stop being trusted.
  # So until a company's state changed twice, the first change was still
  # measured as if the new state had held all hour: a workspace stopped and
  # restarted at :47 billed for the whole hour, exactly the overcharge this was
  # built to end.
  #
  # One row per company, stating what it is now, from now. Every hour after this
  # is read from the log; every hour before it predates the log either way.
  def up
    execute(<<~SQL.squish)
      INSERT INTO company_billing_state_changes (company_id, billing_state, occurred_at, created_at, updated_at)
      SELECT c.id, c.billing_state, NOW(), NOW(), NOW()
        FROM companies c
       WHERE NOT EXISTS (
             SELECT 1 FROM company_billing_state_changes l WHERE l.company_id = c.id
       )
    SQL
  end

  # Irreversible on purpose: there is no telling a backfilled row from one a
  # real change wrote, and deleting the wrong one puts the overcharge back.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
