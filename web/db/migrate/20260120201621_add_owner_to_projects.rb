class AddOwnerToProjects < ActiveRecord::Migration[8.0]
  def change
    add_reference :projects, :owner, null: false, foreign_key: { to_table: :users }
  end
end
