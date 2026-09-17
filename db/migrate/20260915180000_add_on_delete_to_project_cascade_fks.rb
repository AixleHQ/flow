# frozen_string_literal: true

# Adds DB-level ON DELETE cascades/nullifies that mirror the Rails `dependent:`
# declarations on every model in the project-deletion tree. Without these the
# FK constraints block raw DELETE/delete_all operations, forcing manual
# bottom-up cleanup in a console whenever a project must be removed before a
# code deploy. Each entry matches its model's `dependent:` strategy:
#
#   dependent: :destroy / :delete_all  →  on_delete: :cascade
#   dependent: :nullify                →  on_delete: :nullify
#   dependent: :restrict_with_error    →  left as default RESTRICT
class AddOnDeleteToProjectCascadeFks < ActiveRecord::Migration[8.1]
  def change
    # ── children of projects ──────────────────────────────────────────────
    swap_fk :boards,                :projects,       on_delete: :cascade
    swap_fk :integrations,          :projects,       on_delete: :cascade
    swap_fk :project_collaborators, :projects,       on_delete: :cascade
    swap_fk :project_favorites,     :projects,       on_delete: :cascade
    swap_fk :terminal_sessions,     :projects,       on_delete: :nullify
    swap_fk :workflow_runs,         :projects,       on_delete: :cascade

    # ── children of boards ────────────────────────────────────────────────
    swap_fk :board_activities,   :boards, on_delete: :cascade
    swap_fk :board_columns,      :boards, on_delete: :cascade
    swap_fk :board_tasks,        :boards, on_delete: :cascade
    swap_fk :board_view_presets, :boards, on_delete: :cascade

    # ── children of board_tasks ───────────────────────────────────────────
    swap_fk :board_activities,    :board_tasks,                              on_delete: :cascade
    swap_fk :board_tasks,         :board_tasks, column: :parent_task_id,    on_delete: :nullify
    swap_fk :column_transitions,  :board_tasks,                              on_delete: :cascade
    swap_fk :task_assets,         :board_tasks,                              on_delete: :cascade
    swap_fk :task_comments,       :board_tasks,                              on_delete: :cascade
    swap_fk :workflow_runs,       :board_tasks,                              on_delete: :nullify
    # board_tasks.board_column_id → board_columns stays RESTRICT (intentional)

    # ── children of board_columns ─────────────────────────────────────────
    swap_fk :column_transitions,      :board_columns, column: :from_column_id, on_delete: :cascade
    swap_fk :column_transitions,      :board_columns, column: :to_column_id,   on_delete: :cascade
    swap_fk :column_workflow_bindings, :board_columns,                          on_delete: :cascade

    # ── children of integrations ──────────────────────────────────────────
    swap_fk :azure_devops_operations,    :integrations, on_delete: :cascade
    swap_fk :azure_devops_subscriptions, :integrations, on_delete: :cascade
    swap_fk :repositories,               :integrations, on_delete: :cascade

    # ── children of workflows ─────────────────────────────────────────────
    swap_fk :column_workflow_bindings, :workflows, on_delete: :cascade
    swap_fk :steps,                    :workflows, on_delete: :cascade
    swap_fk :workflow_runs,            :workflows, on_delete: :cascade

    # ── children of workflow_runs ─────────────────────────────────────────
    swap_fk :column_transitions,  :workflow_runs, on_delete: :nullify
    swap_fk :step_runs,           :workflow_runs, on_delete: :cascade
    swap_fk :workflow_run_assets, :workflow_runs, on_delete: :cascade

    # ── children of steps ─────────────────────────────────────────────────
    swap_fk :step_runs, :steps, on_delete: :cascade

    # ── children of step_runs ─────────────────────────────────────────────
    swap_fk :sub_step_runs, :step_runs, on_delete: :cascade

    # ── children of tools ─────────────────────────────────────────────────
    swap_fk :tool_files,   :tools, on_delete: :cascade
    swap_fk :tool_results, :tools, on_delete: :cascade

    # ── children of mcp_servers ───────────────────────────────────────────
    swap_fk :oauth_clients,     :mcp_servers, on_delete: :cascade
    swap_fk :oauth_credentials, :mcp_servers, on_delete: :cascade

    # ── children of assets ────────────────────────────────────────────────
    swap_fk :asset_versions, :assets, on_delete: :cascade
  end

  private

  def swap_fk(from_table, to_table, on_delete:, column: nil)
    remove_opts = column ? { column: column } : {}
    add_opts = remove_opts.merge(on_delete: on_delete)

    remove_foreign_key from_table, to_table, **remove_opts
    add_foreign_key    from_table, to_table, **add_opts
  end
end
