# frozen_string_literal: true

# Where we host, a company runs free only when Aixle carries it
# (docs/design/tenant-usage-report.md §6). An `active` company that is not
# flagged but has no worker limit, or no Stripe customer to bill, already runs
# free; this flags it, so it is ours on purpose rather than by omission. Nothing
# about what it can run changes. Trialing and blocked companies are left alone:
# neither is free in the same way.
class MarkFreeActiveCompaniesManaged < ActiveRecord::Migration[8.1]
  def up
    return unless Deployment.saas?

    execute(<<~SQL.squish)
      UPDATE companies
      SET managed_by_aixle = TRUE, updated_at = NOW()
      WHERE managed_by_aixle = FALSE
        AND billing_state = 'active'
        AND (
          stripe_customer_id IS NULL
          OR NOT EXISTS (
            SELECT 1 FROM session_concurrency_limits
            WHERE scope_type = 'Company' AND scope_id = companies.id
          )
        )
    SQL
  end

  # Left flagged: the companies flagged here cannot be told from those flagged
  # by hand.
  def down; end
end
