# frozen_string_literal: true

# Per-user favorite ("starred") projects.
#
# A favorite is one person's own ordering preference, never a property of the
# project: two members of the same project have independent rows, and starring
# a project changes nobody else's list. That is why this is a join table rather
# than a column on `projects` — the same reason `project_collaborators` exists
# instead of an array column.
#
# The unique index is the idempotency guarantee the toggle endpoint relies on:
# double-posting a star cannot create a second row.
class CreateProjectFavorites < ActiveRecord::Migration[8.1]
  def change
    create_table :project_favorites do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true

      t.timestamps
    end

    add_index :project_favorites, %i[user_id project_id], unique: true
  end
end
