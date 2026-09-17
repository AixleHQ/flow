# frozen_string_literal: true

# Permanent (hard) user deletion needs the database to *let* a `users` row be
# destroyed. Today 14 user-referencing foreign keys are ON DELETE RESTRICT, so a
# real DELETE is rejected the moment any of them still points at the row.
#
# Personal data (memberships, credentials, favourites, collaborators, terminal
# sessions, board view presets) is removed via `dependent: :destroy` on User, and
# owned projects are transferred to a company heir by
# Users::PermanentDeletionService before the destroy. Everything here is the
# *history / authorship* half: rows that must OUTLIVE the user with their actor
# anonymised. We make those columns nullable where needed and flip their FK to
# ON DELETE :nullify so Postgres nulls the reference instead of blocking the
# delete. The UI renders a null actor/author as "Deleted user".
class EnablePermanentUserDeletion < ActiveRecord::Migration[8.1]
  # Columns currently NOT NULL that must become nullable before their FK can
  # nullify. [table, column].
  NOT_NULL_TO_NULLABLE = [
    %i[board_activities actor_id],
    %i[column_transitions actor_id],
    %i[assets created_by_id],
    %i[asset_versions uploaded_by_id],
    %i[task_assets author_id],
    %i[task_comments author_id],
    %i[integrations connected_by_id],
    %i[workflow_runs user_id]
  ].freeze

  # Every user-referencing FK that must become ON DELETE :nullify. Includes the
  # eight above plus the columns that were already nullable but still RESTRICT.
  # [table, column].
  FKS_TO_NULLIFY = (NOT_NULL_TO_NULLABLE + [
    %i[trigger_events actor_id],
    %i[gates creator_id],
    %i[board_tasks assignee_id],
    %i[workflows published_by_id],
    %i[azure_devops_installations approved_by_id],
    %i[company_memberships invited_by_id]
  ]).freeze

  def up
    NOT_NULL_TO_NULLABLE.each do |table, column|
      change_column_null table, column, true
    end

    FKS_TO_NULLIFY.each do |table, column|
      remove_foreign_key table, column: column
      add_foreign_key table, :users, column: column, on_delete: :nullify
    end
  end

  def down
    FKS_TO_NULLIFY.each do |table, column|
      remove_foreign_key table, column: column
      add_foreign_key table, :users, column: column
    end

    NOT_NULL_TO_NULLABLE.each do |table, column|
      change_column_null table, column, false
    end
  end
end
