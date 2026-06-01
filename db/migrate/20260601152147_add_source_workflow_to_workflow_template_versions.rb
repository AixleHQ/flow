# frozen_string_literal: true

class AddSourceWorkflowToWorkflowTemplateVersions < ActiveRecord::Migration[8.0]
  def change
    add_reference :workflow_template_versions, :source_workflow, foreign_key: { to_table: :workflows }, null: true
  end
end
