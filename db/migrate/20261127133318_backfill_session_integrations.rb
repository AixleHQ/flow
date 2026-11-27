# frozen_string_literal: true

# Gives the workflows and the sessions that exist what they get today
# (docs/design/session-integrations.md §7), so the gates that read a session's integration
# set take nothing away from them.
#
# The service Integrations::Backfill follows the same rules. This migration keeps its own
# SQL: it loads no app class, so a later change to a model cannot change what it does.
# It has no automated test; it is checked by hand (design §9).
#
# Idempotent: a link or a row that exists is not added again. Prints one summary line.
class BackfillSessionIntegrations < ActiveRecord::Migration[8.1]
  LIVE_STATES = "('not_started', 'queued', 'running', 'ready', 'finishing', 'suspended')"

  # The integrations a project's workflow gets: its Coder (the project's, else the company's,
  # the earliest), every active Slack and Teams install the project can see, and its Azure
  # DevOps connections.
  PROJECT_INTEGRATIONS = <<~SQL.squish
    SELECT p.id AS project_id, i.id AS integration_id
    FROM projects p
    JOIN integrations i ON i.company_id = p.company_id AND i.status = 'active'
    WHERE (i.provider IN ('slack', 'teams') AND (i.project_id IS NULL OR i.project_id = p.id))
       OR (i.provider = 'azure_devops' AND i.project_id = p.id)
    UNION
    SELECT p.id, (
      SELECT c.id FROM integrations c
      WHERE c.provider = 'coder' AND c.status = 'active' AND c.company_id = p.company_id
        AND (c.project_id = p.id OR c.project_id IS NULL)
      ORDER BY (c.project_id IS NULL), c.id LIMIT 1
    )
    FROM projects p
  SQL

  # An integration the session's tenant owns (TenantScope.owned): its company's, with no
  # project or the session's project. The ids in a run's shared_context are not trusted.
  OWNED_INTEGRATION = <<~SQL.squish
    i.company_id = COALESCE(s.company_id, (SELECT sp.company_id FROM projects sp WHERE sp.id = s.project_id))
    AND (i.project_id IS NULL OR i.project_id = s.project_id)
  SQL

  def up
    workflows = backfill_workflows
    sessions = backfill_sessions
    say "session integrations: #{workflows} workflow links, #{sessions} session rows"
  end

  def down
    # The rows are inert without the gates; nothing to undo.
  end

  private

  def backfill_workflows
    execute(<<~SQL.squish).cmd_tuples
      INSERT INTO workflow_resource_links (workflow_id, integration_id, position)
      SELECT w.id, pi.integration_id,
             COALESCE((SELECT MAX(l.position) FROM workflow_resource_links l WHERE l.workflow_id = w.id), -1) +
               ROW_NUMBER() OVER (PARTITION BY w.id ORDER BY pi.integration_id)
      FROM workflows w
      JOIN (#{PROJECT_INTEGRATIONS}) pi ON pi.project_id = w.scope_id
      WHERE w.scope_type = 'Project' AND pi.integration_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM workflow_resource_links l
                        WHERE l.workflow_id = w.id AND l.integration_id = pi.integration_id)
    SQL
  end

  def backfill_sessions
    execute(<<~SQL.squish).cmd_tuples
      INSERT INTO session_integrations (terminal_session_id, integration_id)
      SELECT DISTINCT s.id, wanted.integration_id
      FROM terminal_sessions s
      LEFT JOIN step_runs sr ON sr.terminal_session_id = s.id
      LEFT JOIN workflow_runs wr ON wr.id = sr.workflow_run_id
      JOIN LATERAL (
        SELECT l.integration_id FROM workflow_resource_links l
          WHERE wr.id IS NOT NULL AND l.workflow_id = wr.workflow_id AND l.integration_id IS NOT NULL
        UNION
        SELECT l.integration_id FROM step_resource_links l
          WHERE sr.id IS NOT NULL AND l.step_id = sr.step_id AND l.integration_id IS NOT NULL
        UNION
        SELECT r.integration_id FROM session_repositories x JOIN repositories r ON r.id = x.repository_id
          WHERE x.terminal_session_id = s.id AND r.integration_id IS NOT NULL
        UNION
        SELECT i.id FROM integrations i
          WHERE wr.id IS NOT NULL AND i.id::text = (wr.shared_context #>> '{chat,integration_id}')
            AND #{OWNED_INTEGRATION}
        UNION
        SELECT i.id FROM project_trackers t JOIN integrations i ON i.id = t.integration_id
          WHERE wr.id IS NOT NULL AND t.id::text = (wr.shared_context #>> '{tracker,id}')
            AND t.project_id = s.project_id AND #{OWNED_INTEGRATION}
        UNION
        SELECT pi.integration_id FROM (#{PROJECT_INTEGRATIONS}) pi
          WHERE wr.id IS NULL AND s.project_id = pi.project_id AND pi.integration_id IS NOT NULL
      ) wanted ON TRUE
      WHERE s.state IN #{LIVE_STATES}
        AND NOT EXISTS (SELECT 1 FROM session_integrations e
                        WHERE e.terminal_session_id = s.id AND e.integration_id = wanted.integration_id)
    SQL
  end
end
