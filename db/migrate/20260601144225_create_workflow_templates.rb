# frozen_string_literal: true

class CreateWorkflowTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :workflows, :kind, :string, null: false, default: "standard"
    add_index :workflows, :kind

    remove_index :workflows, name: "index_workflows_on_scope_and_name_unique"
    add_index :workflows,
              %i[scope_type scope_id name kind],
              unique: true,
              where: "deleted_at IS NULL",
              name: "index_workflows_on_scope_name_and_kind_unique"

    create_table :workflow_templates do |t|
      t.references :company, null: false, foreign_key: true
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :description
      t.string :use_case
      t.string :visibility, null: false, default: "company"
      t.datetime :archived_at
      t.timestamps
    end

    add_index :workflow_templates, %i[company_id name], unique: true

    create_table :workflow_template_versions do |t|
      t.references :workflow_template, null: false, foreign_key: true
      t.references :workflow, null: false, foreign_key: true
      t.references :published_by, null: false, foreign_key: { to_table: :users }
      t.integer :version_number, null: false
      t.text :changelog
      t.datetime :published_at, null: false
      t.timestamps
    end

    add_index :workflow_template_versions,
              %i[workflow_template_id version_number],
              unique: true,
              name: "index_wf_template_versions_on_template_and_number"

    add_reference :workflow_templates, :current_version,
                  foreign_key: { to_table: :workflow_template_versions },
                  index: true

    add_reference :projects, :workflow_template_version, foreign_key: true, index: true
  end
end
