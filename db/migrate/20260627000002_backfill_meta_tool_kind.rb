# frozen_string_literal: true

# Backfills the new :meta tool kind for the Aixle Builder meta_* tools. Platform
# tools are seeded via db/seeds/platform_tools.rb (run on deploy by db:seed), but
# a migration guarantees existing meta_* tools flip from :workflow to :meta on
# every environment without relying on the seed step. Idempotent.
class BackfillMetaToolKind < ActiveRecord::Migration[8.0]
  # Decoupled from the app Tool model so this migration keeps working regardless
  # of future model validations/callbacks.
  class MigrationTool < ActiveRecord::Base
    self.table_name = "tools"
  end

  def up
    MigrationTool.where("name LIKE 'meta\\_%' AND kind = 'workflow'").update_all(kind: "meta")
  end

  def down
    MigrationTool.where("name LIKE 'meta\\_%' AND kind = 'meta'").update_all(kind: "workflow")
  end
end
