# frozen_string_literal: true

# Enforce the new scoping rules: MCP servers, Skills, Agents, Workflows, custom
# Tools, Config items and Repositories may no longer live at the Company level —
# only at Project scope (Workflows also keep the single System-scoped "Aixle
# Builder"; Assets and Integrations keep Company scope). Coder tools now surface
# in-process through aixle-tools like Slack, so `managed` MCP servers (the
# integration-owned mirror rows) are removed and the dead `integration_id`
# column is dropped. Agents drop the System scope entirely (the Builder's
# persona is inlined into its step).
#
# This migration DELETES the offending rows. The data deletion is irreversible;
# `down` only restores the dropped column so schema.rb round-trips.
class RestrictResourceScopesToProject < ActiveRecord::Migration[8.0]
  def up
    # --- MCP servers: drop managed rows and any company-scoped custom rows ---
    # oauth_credentials FK to mcp_servers is RESTRICT, so clear children first.
    say_with_time "Removing managed and company-scoped MCP servers" do
      execute(<<~SQL.squish)
        DELETE FROM oauth_credentials
        WHERE mcp_server_id IN (
          SELECT id FROM mcp_servers WHERE kind = 'managed' OR scope_type = 'Company'
        )
      SQL
      execute("DELETE FROM mcp_servers WHERE kind = 'managed' OR scope_type = 'Company'")
    end

    # --- Drop the now-dead integration_id column (managed servers only) ---
    remove_reference :mcp_servers, :integration, index: true, foreign_key: true

    # --- Skills: company scope removed ---
    say_with_time "Removing company-scoped skills" do
      execute("DELETE FROM skills WHERE scope_type = 'Company'")
    end

    # --- Config items: company scope removed (secrets/vars are per-project now) ---
    say_with_time "Removing company-scoped config items" do
      execute("DELETE FROM config_items WHERE scope_type = 'Company'")
    end

    # --- Repositories: company scope removed (session_repositories cascades) ---
    say_with_time "Removing company-scoped repositories" do
      execute("DELETE FROM repositories WHERE scope_type = 'Company'")
    end

    # Tools and workflows are deleted in SQL, children first, following the foreign
    # keys as they stood on this date — not through the models, whose callbacks and
    # associations are today's and would run against this date's schema (and reach
    # Temporal and object storage from inside a migration). What the callbacks did
    # besides deleting rows is left behind on purpose: stored files stay in object
    # storage, and the Temporal schedules of deleted schedule bindings are pruned by
    # ScheduleReconciler.reconcile_all on the next worker boot.

    # --- Custom (db-source) tools: company scope removed. tool_files / tool_results
    # are RESTRICT FKs; session_tools cascade at the DB. Code/platform tool rows
    # (scope-less) are untouched. ---
    say_with_time "Removing company-scoped custom tools" do
      tools = "SELECT id FROM tools WHERE source = 'db' AND scope_type = 'Company'"
      execute("DELETE FROM tool_files WHERE tool_id IN (#{tools})")
      execute("DELETE FROM tool_results WHERE tool_id IN (#{tools})")
      execute("DELETE FROM tools WHERE id IN (#{tools})")
    end

    # --- Agents: company AND system scope removed (steps.agent_id and
    # terminal_sessions.configured_agent_id FKs both ON DELETE nullify) ---
    say_with_time "Removing company- and system-scoped agents" do
      execute("DELETE FROM agents WHERE scope_type IN ('Company', 'System')")
    end

    # --- Workflows: company scope removed (System "Aixle Builder" stays) ---
    # RESTRICT: column_workflow_bindings, steps, workflow_runs -> workflows;
    # sub_steps, step_runs -> steps; step_runs, workflow_run_assets,
    # column_transitions (kept, unlinked) -> workflow_runs; sub_step_runs ->
    # step_runs and sub_steps. trigger_bindings cascade; trigger_dispatches,
    # tool_results and produced run assets are nullified by the DB.
    say_with_time "Removing company-scoped workflows" do
      workflows = "SELECT id FROM workflows WHERE scope_type = 'Company'"
      runs = "SELECT id FROM workflow_runs WHERE workflow_id IN (#{workflows})"
      steps = "SELECT id FROM steps WHERE workflow_id IN (#{workflows})"
      step_runs = "SELECT id FROM step_runs WHERE step_id IN (#{steps}) OR workflow_run_id IN (#{runs})"
      execute("DELETE FROM column_workflow_bindings WHERE workflow_id IN (#{workflows})")
      execute("UPDATE column_transitions SET workflow_run_id = NULL WHERE workflow_run_id IN (#{runs})")
      execute(<<~SQL.squish)
        DELETE FROM sub_step_runs
        WHERE step_run_id IN (#{step_runs}) OR sub_step_id IN (SELECT id FROM sub_steps WHERE step_id IN (#{steps}))
      SQL
      execute("DELETE FROM workflow_run_assets WHERE workflow_run_id IN (#{runs})")
      execute("DELETE FROM step_runs WHERE id IN (#{step_runs})")
      execute("DELETE FROM sub_steps WHERE step_id IN (#{steps})")
      execute("DELETE FROM steps WHERE id IN (#{steps})")
      execute("DELETE FROM workflow_runs WHERE id IN (#{runs})")
      execute("DELETE FROM workflows WHERE id IN (#{workflows})")
    end
  end

  def down
    # Structural rollback only — deleted rows are not restored.
    add_reference :mcp_servers, :integration, type: :bigint, index: true,
                  foreign_key: { on_delete: :cascade }
  end
end
