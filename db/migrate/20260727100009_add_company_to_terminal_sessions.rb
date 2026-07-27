# frozen_string_literal: true

# Per-company agent credentials force this column. A project-bound session gets
# its company from the project, but `auth_setup` sessions are deliberately
# project-less — and those are exactly the sessions that CREATE a credential. If
# the company were guessed (previously: the user's first membership), a
# multi-company user could authenticate a token into the wrong company and bill
# the wrong tenant.
#
# Nullable: historical rows may have no project and no way to infer a company.
# Readers must keep falling back to project.company_id, which stays the source of
# truth for project-bound sessions.
class AddCompanyToTerminalSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :terminal_sessions, :company_id, :bigint
    add_index :terminal_sessions, :company_id

    # Project-bound rows: copy the company the project already implies, so the
    # column is consistent wherever it is set.
    execute <<~SQL
      UPDATE terminal_sessions ts
      SET company_id = p.company_id
      FROM projects p
      WHERE p.id = ts.project_id
    SQL

    # Project-less rows (auth_setup and legacy): attribute to the owner's single
    # membership when there is exactly one, otherwise leave NULL rather than
    # guess.
    execute <<~SQL
      UPDATE terminal_sessions ts
      SET company_id = sole.company_id
      FROM (
        SELECT user_id, MIN(company_id) AS company_id
        FROM company_memberships
        GROUP BY user_id
        HAVING COUNT(*) = 1
      ) sole
      WHERE ts.project_id IS NULL AND sole.user_id = ts.user_id
    SQL

    add_foreign_key :terminal_sessions, :companies
  end

  def down
    remove_foreign_key :terminal_sessions, :companies
    remove_index :terminal_sessions, :company_id
    remove_column :terminal_sessions, :company_id
  end
end
