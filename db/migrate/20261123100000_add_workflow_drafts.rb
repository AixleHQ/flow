# frozen_string_literal: true

# A workflow draft is a hidden copy of a workflow (docs/design/workflow-drafts.md): it is
# edited and test-run like any workflow, and applying it writes it onto the original. Its
# steps and sub-steps remember the rows they were copied from, so applying it updates
# those rows instead of replacing them. A draft keeps its original's name, so the name
# rule only holds among workflows that are not drafts.
class AddWorkflowDrafts < ActiveRecord::Migration[8.1]
  def change
    add_reference :workflows, :draft_of, foreign_key: { to_table: :workflows, on_delete: :cascade }, index: false
    add_column :workflows, :draft_base_version, :integer
    add_index :workflows, :draft_of_id, unique: true, where: "draft_of_id IS NOT NULL AND deleted_at IS NULL",
                                        name: "index_workflows_on_open_draft"
    add_index :workflows, :draft_of_id, where: "draft_of_id IS NOT NULL", name: "index_workflows_on_draft_of_id"

    add_reference :steps, :origin_step, foreign_key: { to_table: :steps, on_delete: :nullify },
                                        index: { where: "origin_step_id IS NOT NULL" }
    add_reference :sub_steps, :origin_sub_step, foreign_key: { to_table: :sub_steps, on_delete: :nullify },
                                                index: { where: "origin_sub_step_id IS NOT NULL" }

    remove_index :workflows, %i[scope_type scope_id name], unique: true, where: "(deleted_at IS NULL)",
                                                          name: "index_workflows_on_scope_and_name_unique"
    add_index :workflows, %i[scope_type scope_id name], unique: true,
                                                       where: "deleted_at IS NULL AND draft_of_id IS NULL",
                                                       name: "index_workflows_on_scope_and_name_unique"
  end
end
