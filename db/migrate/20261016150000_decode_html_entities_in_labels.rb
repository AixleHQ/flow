# frozen_string_literal: true

# Step, sub-step and board-task labels are now decoded on write (DecodesHtmlEntities);
# this pass decodes the rows agents already stored escaped, e.g. "Plan &amp; release
# next batch". Workflow names are decoded on write too but skipped here: none are
# escaped on prod, and decoding one could collide with index_workflows_on_scope_and_name_unique.
#
# Idempotent: a decoded label no longer matches the entity pattern.
class DecodeHtmlEntitiesInLabels < ActiveRecord::Migration[8.1]
  ENTITY = "&(amp|lt|gt|quot|apos|#[0-9]+|#x[0-9a-fA-F]+);"

  class MigStep < ActiveRecord::Base
    self.table_name = "steps"
  end

  class MigSubStep < ActiveRecord::Base
    self.table_name = "sub_steps"
  end

  class MigBoardTask < ActiveRecord::Base
    self.table_name = "board_tasks"
  end

  def up
    { MigStep => :name, MigSubStep => :name, MigBoardTask => :title }.each do |model, column|
      model.where("#{column} ~ ?", ENTITY).find_each do |row|
        row.update_columns(column => CGI.unescapeHTML(row[column]))
      end
    end
  end

  # Not reversible: an escaped label is never what anyone meant to store.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
