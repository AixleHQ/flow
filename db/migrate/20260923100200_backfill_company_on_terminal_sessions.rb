# frozen_string_literal: true

# Every session acts for exactly one company. The column was nullable and set only
# some of the time, so the company was read from three places — the column, the
# project, and for legacy rows every company the owner belonged to — and the last
# of those showed a person's project-less sessions to all of their companies.
#
# This release backfills and the model requires the company. The database check
# comes one release later: pods of the previous release — mid-rollout, or after a
# rollback — still create project-less sessions without one, and a CHECK, even
# NOT VALID, would refuse those inserts. The follow-up re-runs this backfill, adds
# the check and validates it; a row still without a company then belongs to
# someone with no membership anywhere.
class BackfillCompanyOnTerminalSessions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE terminal_sessions
         SET company_id = projects.company_id
        FROM projects
       WHERE terminal_sessions.project_id = projects.id
         AND terminal_sessions.company_id IS NULL
    SQL

    # Project-less legacy rows: the owner's remembered company when they belong to
    # it, otherwise the membership they have held longest.
    execute <<~SQL
      UPDATE terminal_sessions
         SET company_id = COALESCE(
               (SELECT m.company_id FROM company_memberships m JOIN users u ON u.id = m.user_id
                 WHERE m.user_id = terminal_sessions.user_id AND m.company_id = u.last_company_id
                 LIMIT 1),
               (SELECT m.company_id FROM company_memberships m
                 WHERE m.user_id = terminal_sessions.user_id
                 ORDER BY m.accepted_at NULLS LAST, m.id
                 LIMIT 1))
       WHERE company_id IS NULL
    SQL
  end

  def down; end
end
