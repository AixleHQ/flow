# frozen_string_literal: true

# Admission is no longer something an installation switches on or pauses: every
# session goes through the queue. The columns stay for one release because pods
# still running the previous image read them during the rollout, and they must
# see the queue as on and granting too; a follow-up drops them.
class AlwaysEnableSessionAdmission < ActiveRecord::Migration[8.1]
  def up
    change_column_default :session_admission_policies, :enabled, from: false, to: true
    change_column_default :session_admission_policies, :paused, from: true, to: false
    execute <<~SQL.squish
      UPDATE session_admission_policies
      SET enabled = TRUE, paused = FALSE, revision = revision + 1, updated_at = CURRENT_TIMESTAMP
      WHERE enabled = FALSE OR paused = TRUE
    SQL
  end

  def down
    change_column_default :session_admission_policies, :paused, from: false, to: true
    change_column_default :session_admission_policies, :enabled, from: true, to: false
  end
end
