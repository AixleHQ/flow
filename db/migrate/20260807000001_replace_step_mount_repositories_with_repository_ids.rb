# frozen_string_literal: true

# Repositories become a chosen resource instead of a boolean.
#
# `mount_repositories` said "this step wants code" but never said *which* code —
# the list came from the run, or from a project-wide fallback that only fired for
# board-triggered runs. A scheduled workflow therefore had no way to get a
# repository at all. Steps now carry `repository_ids` exactly the way they already
# carry `tool_ids`, `skill_ids` and `mcp_server_ids`, and workflows carry
# `config["base_repository_ids"]` alongside the other `base_*_ids`.
#
# The backfill is the reason this migration is not a plain drop_column: over half
# the steps in production keep the flag OFF, and that is a real "no code here"
# decision (report builders, planners, intake steps). Resolution unions the levels,
# so a workflow-level list would reach every step and silently undo each of those
# opt-outs. The repositories are therefore written per step, and only to the steps
# that had the flag ON in a workflow that inherited project resources — which is
# precisely the set that resolves to a repository today.
class ReplaceStepMountRepositoriesWithRepositoryIds < ActiveRecord::Migration[8.1]
  def up
    add_column :steps, :repository_ids, :jsonb, default: [], null: false

    # Steps whose repositories came from the project-wide fallback keep them as an
    # explicit list. Steps with the flag off keep the column's empty default.
    execute(<<~SQL.squish)
      UPDATE steps
         SET repository_ids = inherited.repository_ids
        FROM (
              SELECT w.id AS workflow_id,
                     jsonb_agg(r.id ORDER BY r.id) AS repository_ids
                FROM workflows w
                JOIN repositories r
                  ON r.scope_type = 'Project'
                 AND r.scope_id = w.scope_id
               WHERE w.deleted_at IS NULL
                 AND w.scope_type = 'Project'
                 AND COALESCE((w.config ->> 'inherit_all_project_resources')::boolean, false)
               GROUP BY w.id
             ) AS inherited
       WHERE steps.workflow_id = inherited.workflow_id
         AND steps.deleted_at IS NULL
         AND steps.mount_repositories
    SQL

    remove_column :steps, :mount_repositories
  end

  def down
    add_column :steps, :mount_repositories, :boolean, default: true, null: false

    # The flag cannot express *which* repositories, so the rollback keeps the only
    # part it can carry: whether this step mounted any.
    execute(<<~SQL.squish)
      UPDATE steps
         SET mount_repositories = (repository_ids <> '[]'::jsonb)
    SQL

    remove_column :steps, :repository_ids
  end
end
