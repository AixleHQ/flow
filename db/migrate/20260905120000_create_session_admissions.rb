# frozen_string_literal: true

class CreateSessionAdmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :session_admission_policies do |t|
      t.boolean :enabled, null: false, default: false
      t.boolean :paused, null: false, default: true
      t.integer :installation_limit
      t.integer :revision, null: false, default: 1
      t.timestamps
    end
    add_check_constraint :session_admission_policies, "id = 1 AND (installation_limit IS NULL OR installation_limit > 0)", name: "valid_session_policy"
    reversible { |dir| dir.up { seed_policy } }
    create_table :session_concurrency_limits do |t|
      t.string :scope_type, null: false
      t.bigint :scope_id, null: false
      t.integer :max_sessions, null: false
      t.timestamps
    end
    add_index :session_concurrency_limits, [ :scope_type, :scope_id ], unique: true
    add_check_constraint :session_concurrency_limits, "max_sessions > 0 AND scope_type IN ('Project', 'User')", name: "valid_session_scope_limit"
    create_table :session_admission_pools do |t|
      t.string :key, null: false
      t.integer :limit, null: false
      t.integer :policy_revision, null: false
      t.timestamps
    end
    add_index :session_admission_pools, :key, unique: true
    add_check_constraint :session_admission_pools, '"limit" > 0', name: "positive_session_pool_limit"
    create_table :session_admissions do |t|
      t.references :terminal_session, null: false, foreign_key: true, index: { unique: true }
      t.references :session_admission_pool, null: false, foreign_key: true
      t.string :permit_token
      t.datetime :admitted_at
      t.datetime :released_at
      t.datetime :stop_requested_at
      t.string :launch_state, null: false, default: "pending"
      t.datetime :claimed_at
      t.string :claim_token
      t.string :runtime_id
      t.string :runtime_kind
      t.jsonb :phase_state, null: false, default: {}
      t.string :wait_reason, default: "concurrency_limit"
      t.text :last_error
      t.timestamps
    end
    add_index :session_admissions, :permit_token, unique: true
    add_index :session_admissions, [ :session_admission_pool_id, :id ], where: "released_at IS NULL", name: "session_admission_fifo"
    create_table :session_runtime_operations do |t|
      t.references :session_admission, null: false, foreign_key: true
      t.string :phase, null: false
      t.string :state, null: false, default: "in_flight"
      t.jsonb :result, null: false, default: {}
      t.text :error
      t.timestamps
    end
    add_index :session_runtime_operations, [ :session_admission_id, :phase ], unique: true, name: "session_runtime_phase_once"
    add_column :terminal_sessions, :queued_at, :datetime
    add_column :workflow_runs, :stop_requested_at, :datetime
  end

  # A database with no sessions and no runs has never served anyone: this is a
  # fresh installation, there is nothing to drain, and admission can start on.
  # An installation with history is an upgrade — enabling here would put live
  # sessions behind a queue they were never admitted to, so it stays off until
  # an operator performs the cutover (session_admission:sync, or the button in
  # the admin).
  def fresh_installation?
    select_value("SELECT 1 FROM terminal_sessions LIMIT 1").nil? &&
      select_value("SELECT 1 FROM workflow_runs LIMIT 1").nil?
  end

  # The cap is read from the environment once, here, because a brand-new
  # installation has no other way to learn it and nobody to run a task.
  # Everything afterwards goes through the policy row.
  def seed_policy
    execute <<~SQL.squish
      INSERT INTO session_admission_policies (id, created_at, updated_at)
      VALUES (1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    return unless fresh_installation?

    cap = ENV["SESSION_CONCURRENCY_LIMIT"].to_s.strip
    cap = "NULL" unless cap.match?(/\A[1-9]\d*\z/)
    execute <<~SQL.squish
      UPDATE session_admission_policies
      SET enabled = TRUE, paused = FALSE, installation_limit = #{cap}, updated_at = CURRENT_TIMESTAMP
      WHERE id = 1
    SQL
  end
end
