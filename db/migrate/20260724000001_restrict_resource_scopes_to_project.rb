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

    # --- Custom (db-source) tools: company scope removed. Destroy via the model
    # so tool_files / tool_results (both RESTRICT FKs) are torn down; session_tools
    # cascade at the DB. Code/platform tool rows (scope-less) are untouched. ---
    say_with_time "Removing company-scoped custom tools" do
      Tool.where(source: "db", scope_type: "Company").find_each(&:destroy!)
    end

    # --- Agents: company AND system scope removed (steps.agent_id and
    # terminal_sessions.configured_agent_id FKs both ON DELETE nullify) ---
    say_with_time "Removing company- and system-scoped agents" do
      execute("DELETE FROM agents WHERE scope_type IN ('Company', 'System')")
    end

    # --- Workflows: company scope removed (System "Aixle Builder" stays) ---
    # Use the model so the full dependent chain (steps, sub-steps, runs, step
    # runs, run assets, trigger bindings) is torn down correctly. column_
    # transitions -> workflow_runs is RESTRICT with no dependent, so null it
    # first; column_workflow_bindings -> workflows is also RESTRICT.
    say_with_time "Removing company-scoped workflows" do
      Workflow.where(scope_type: "Company").find_each do |workflow|
        run_ids = workflow.runs.ids
        ColumnTransition.where(workflow_run_id: run_ids).update_all(workflow_run_id: nil) if run_ids.any?
        ColumnWorkflowBinding.where(workflow_id: workflow.id).delete_all
        workflow.destroy!
      end
    end
  end

  def down
    # Structural rollback only — deleted rows are not restored.
    add_reference :mcp_servers, :integration, type: :bigint, index: true,
                  foreign_key: { on_delete: :cascade }
  end
end
