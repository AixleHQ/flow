# frozen_string_literal: true

# Stage 4 of the code-first tool registry: the legacy kind enum dies. Its
# axes live on as source (custom vs platform), tags (grouping), inject rules
# (code-only) and user_attachable (picker visibility).
class DropToolKind < ActiveRecord::Migration[8.1]
  class MigrationTool < ActiveRecord::Base
    self.table_name = "tools"
  end

  def up
    remove_index :tools, column: :kind, if_exists: true
    remove_column :tools, :kind
  end

  # Best-effort restore from the surviving axes — enough for a rollback to
  # pre-Stage-4 code, which reads kind for scopes and auto-injection.
  def down
    add_column :tools, :kind, :string, null: false, default: "custom"
    add_index :tools, :kind

    MigrationTool.reset_column_information
    MigrationTool.where(source: "code").in_batches do |batch|
      batch.each do |row|
        tags = Array(row.tags)
        row.update_columns(kind: kind_from_tags(tags))
      end
    end
  end

  private

  def kind_from_tags(tags)
    return "meta" if tags.include?("builder")
    return "system" if tags.include?("coder")
    return "internal" if tags.intersect?(%w[session_lifecycle async_results])

    "workflow"
  end
end
