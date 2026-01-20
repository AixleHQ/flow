class RemoveRoleFromProjectCollaborators < ActiveRecord::Migration[8.0]
  def change
    remove_index :project_collaborators, :role
    remove_column :project_collaborators, :role, :string
  end
end
