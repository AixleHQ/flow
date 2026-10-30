# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.4: the runner a workflow declares, the
# runner a run resolved to, and the runner a session used. Nullable, no default
# and no backfill, so every existing row reads as hosted.
#
# workflows and terminal_sessions carry company_id, so their key also ties the
# runner's company to theirs, the tenant-key pattern of §2. workflow_runs has no
# company column; its runner is checked against its project by the model.
class AddRunnerReferences < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLES = %i[workflows workflow_runs terminal_sessions].freeze
  TENANT_KEYED = %i[workflows terminal_sessions].freeze

  def up
    add_index :runners, %i[id company_id], unique: true, algorithm: :concurrently, if_not_exists: true

    TABLES.each do |table|
      add_column table, :runner_id, :bigint, if_not_exists: true
      add_index table, :runner_id, algorithm: :concurrently, if_not_exists: true
      add_foreign_key table, :runners, validate: false, if_not_exists: true
      validate_foreign_key table, :runners
    end

    TENANT_KEYED.each do |table|
      name = "fk_#{table}_runner_company"
      next if foreign_key_exists?(table, name: name)

      add_foreign_key table, :runners, column: %i[runner_id company_id], primary_key: %i[id company_id],
                                       validate: false, name: name
      validate_foreign_key table, name: name
    end
  end

  def down
    TENANT_KEYED.each do |table|
      remove_foreign_key table, name: "fk_#{table}_runner_company", if_exists: true
    end
    TABLES.each do |table|
      remove_foreign_key table, :runners, if_exists: true
      remove_column table, :runner_id, if_exists: true
    end
    remove_index :runners, %i[id company_id], if_exists: true
  end
end
