# frozen_string_literal: true

class AddExecutionStartedAtToWorkflowRuns < ActiveRecord::Migration[8.1]
  def up
    add_column :workflow_runs, :execution_started_at, :datetime

    execute(<<~SQL.squish)
      UPDATE workflow_runs SET execution_started_at = first_start.started_at
      FROM (
        SELECT step_runs.workflow_run_id, MIN(terminal_sessions.started_at) AS started_at
        FROM step_runs JOIN terminal_sessions ON terminal_sessions.id = step_runs.terminal_session_id
        GROUP BY step_runs.workflow_run_id
      ) first_start
      WHERE workflow_runs.id = first_start.workflow_run_id AND first_start.started_at IS NOT NULL
    SQL

    # A run whose step sessions are gone leaves nothing to read the start from, so
    # it keeps the duration it had. One whose sessions never left the queue did
    # not execute at all and stays empty.
    execute(<<~SQL.squish)
      UPDATE workflow_runs SET execution_started_at = workflow_runs.started_at
      WHERE workflow_runs.execution_started_at IS NULL
        AND workflow_runs.state IN ('completed', 'failed', 'cancelled')
        AND NOT EXISTS (
          SELECT 1 FROM step_runs JOIN terminal_sessions ON terminal_sessions.id = step_runs.terminal_session_id
          WHERE step_runs.workflow_run_id = workflow_runs.id
        )
    SQL
  end

  def down
    remove_column :workflow_runs, :execution_started_at
  end
end
