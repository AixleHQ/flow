# frozen_string_literal: true

class BackfillTemplateSnapshotKindOnWorkflows < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE workflows
      SET kind = 'template_snapshot'
      WHERE id IN (SELECT workflow_id FROM workflow_template_versions)
        AND kind != 'template_snapshot'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE workflows
      SET kind = 'standard'
      WHERE id IN (SELECT workflow_id FROM workflow_template_versions)
        AND kind = 'template_snapshot'
    SQL
  end
end
