class CreateProjectCollaborators < ActiveRecord::Migration[8.0]
  def change
    create_table :project_collaborators do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      # Role within project: viewer, contributor (default), manager
      t.string :role, null: false, default: "contributor"

      t.timestamps
    end

    # One user can only be a collaborator once per project
    add_index :project_collaborators, [:project_id, :user_id], unique: true
    add_index :project_collaborators, :role
  end
end
