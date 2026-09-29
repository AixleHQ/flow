# frozen_string_literal: true

# Adds the Company scope, which is the tier the product actually sells.
#
# The installation ceiling used to be the budget every project reservation was
# drawn from — one number for the whole deployment, read from the environment.
# That works for a single-tenant install and nothing else: a customer running
# several organisations in one installation had no way to give each of them a
# limit, and there was no per-organisation number to bill for.
#
# So the budget moves down a tier. A project now reserves out of its own
# company's limit, a company's limit is the number that gets charged for, and
# the installation ceiling keeps only the job it could always do honestly:
# clamping what the cluster is physically able to run.
#
# The User scope is already gone (20260917150000); this replaces it in the
# constraint rather than widening the list to three.
class AllowCompanySessionConcurrencyLimits < ActiveRecord::Migration[8.1]
  CONSTRAINT = "valid_session_scope_limit"

  def up
    remove_check_constraint :session_concurrency_limits, name: CONSTRAINT
    add_check_constraint :session_concurrency_limits,
                         "max_sessions > 0 AND scope_type::text = ANY (ARRAY['Project'::character varying, 'Company'::character varying]::text[])",
                         name: CONSTRAINT
  end

  def down
    # Company rows are meaningless without the scope, and leaving them would make
    # the old constraint unaddable. Drop them first, then restore the previous
    # definition verbatim.
    deleted = execute("DELETE FROM session_concurrency_limits WHERE scope_type = 'Company'").cmd_tuples
    say "Removed #{deleted} company-scoped session concurrency limit(s)" if deleted.positive?

    remove_check_constraint :session_concurrency_limits, name: CONSTRAINT
    add_check_constraint :session_concurrency_limits,
                         "max_sessions > 0 AND scope_type::text = ANY (ARRAY['Project'::character varying, 'User'::character varying]::text[])",
                         name: CONSTRAINT
  end
end
