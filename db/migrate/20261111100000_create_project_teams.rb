# frozen_string_literal: true

# docs/design/project-teams.md: a team is a named group of a project's members
# that a board task can be assigned to and an off-board trigger can run as; each
# run resolves it to one member.
class CreateProjectTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :project_teams do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :strategy, null: false, default: "priority"
      t.bigint :last_picked_user_id
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
      t.index %i[project_id name], unique: true
    end

    create_table :project_team_members do |t|
      t.references :project_team, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false, default: 0
      t.references :added_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
      t.index %i[project_team_id user_id], unique: true
    end

    add_reference :board_tasks, :assignee_team, foreign_key: { to_table: :project_teams, on_delete: :nullify }
    add_check_constraint :board_tasks, "num_nonnulls(assignee_id, assignee_team_id) <= 1",
                         name: "board_tasks_one_assignee"

    add_reference :trigger_bindings, :run_as_team, foreign_key: { to_table: :project_teams, on_delete: :nullify }
    add_reference :workflow_runs, :team, foreign_key: { to_table: :project_teams, on_delete: :nullify }

    add_column :agent_credentials, :quota_exhausted_until, :datetime
    add_column :users, :exclude_from_teams, :boolean, null: false, default: false
  end
end
