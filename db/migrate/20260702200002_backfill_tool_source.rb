# frozen_string_literal: true

# Backfills tools.source from the legacy kind enum and adds the partial unique
# index the reconciler upserts against. The existing (scope_type, scope_id, name)
# unique index does NOT enforce platform-name uniqueness because platform rows
# have NULL scope and Postgres treats NULLs as distinct — so duplicates are
# soft-deleted (keep lowest id) before the new index is created. Idempotent.
class BackfillToolSource < ActiveRecord::Migration[8.1]
  # Decoupled from the app Tool model so this migration keeps working
  # regardless of future model validations/callbacks.
  class MigrationTool < ActiveRecord::Base
    self.table_name = "tools"
  end

  PLATFORM_KINDS = %w[system internal workflow meta].freeze

  def up
    MigrationTool.where(kind: PLATFORM_KINDS).update_all(source: "code")
    MigrationTool.where(kind: "meta").update_all(user_attachable: false)

    dedup_platform_names!

    add_index :tools, :name, unique: true,
              where: "source = 'code' AND deleted_at IS NULL",
              name: :index_tools_on_name_where_source_code
  end

  def down
    remove_index :tools, name: :index_tools_on_name_where_source_code
    # kind is untouched, so pre-refactor code never reads source/user_attachable.
    MigrationTool.update_all(source: "db", user_attachable: true)
  end

  private

  def dedup_platform_names!
    duplicate_names = MigrationTool.where(source: "code", deleted_at: nil)
                                   .group(:name).having("COUNT(*) > 1").pluck(:name)
    duplicate_names.each do |name|
      rows = MigrationTool.where(source: "code", deleted_at: nil, name: name).order(:id).to_a
      rows.drop(1).each { |row| row.update_columns(deleted_at: Time.current, enabled: false) }
      say "Deduplicated platform tool name #{name}: kept ##{rows.first.id}, soft-deleted #{rows.drop(1).map(&:id)}"
    end
  end
end
