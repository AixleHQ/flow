# frozen_string_literal: true

module Coder
  # LockService — atomic, DB-backed workspace locks for a Coder integration.
  #
  # Locks are stored in `integration_data` with key
  # `coder:workspace_lock:<workspace_name>`. The unique index on
  # `(integration_id, key)` is what serialises concurrent acquisitions, and
  # the atomic `INSERT … ON CONFLICT (integration_id, key) DO UPDATE …
  # WHERE existing.expires_at <= EXCLUDED.created_at` clause is what lets
  # expired rows be reclaimed in a single statement (no read-modify-write race).
  #
  # Ownership is keyed on `terminal_session_id` (N2 / DD-13): the lock value
  # records which terminal session holds the workspace, and the teardown hook
  # in `WorkflowStepStrategy` releases by session id when the step ends.
  class LockService
    LOCK_KEY_PREFIX = "coder:workspace_lock:"

    class LockNotAcquired < StandardError; end

    # Release every Coder workspace lock held by the given terminal session,
    # iterating every active Coder integration visible to the session's
    # project scope. Safe to call when no integration is configured — the
    # per-integration `release_for_session` is a cheap single-statement
    # delete on miss. Errors are logged and swallowed so a single
    # misbehaving integration cannot block step teardown.
    def self.release_all_for_session(session)
      project = session&.project
      return unless project

      Integration.where(provider: :coder, status: :active)
                 .where(company_id: project.company_id)
                 .where("project_id IS NULL OR project_id = ?", project.id)
                 .find_each do |integration|
        new(integration).release_for_session(terminal_session_id: session.id)
      rescue StandardError => e
        Rails.logger.warn("[Coder::LockService] release for integration #{integration.id} failed: #{e.message}")
      end
    end

    def initialize(integration)
      @integration = integration
    end

    # Atomic acquire. Returns the `IntegrationData` row on success, raises
    # `LockNotAcquired` if another live lock already holds the workspace.
    def acquire(workspace_name:, workspace_id:, terminal_session_id:,
                note: nil, acquired_by: nil)
      now        = Time.current
      expires_at = now + ttl_minutes.minutes
      payload    = {
        kind:                "workspace_lock",
        workspace_id:        workspace_id.to_s,
        terminal_session_id: terminal_session_id.to_s,
        acquired_at:         now.iso8601,
        acquired_by:         acquired_by.to_s,
        note:                note.to_s
      }.compact_blank

      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish,
          INSERT INTO integration_data
            (integration_id, key, value, expires_at, created_at, updated_at)
          VALUES (?, ?, ?::jsonb, ?, ?, ?)
          ON CONFLICT (integration_id, key) DO UPDATE
            SET value      = EXCLUDED.value,
                expires_at = EXCLUDED.expires_at,
                updated_at = EXCLUDED.updated_at
            WHERE integration_data.expires_at IS NOT NULL
              AND integration_data.expires_at <= EXCLUDED.created_at
        SQL
        @integration.id,
        lock_key(workspace_name),
        payload.to_json,
        expires_at,
        now,
        now
      ])
      ActiveRecord::Base.connection.execute(sql)

      row = lock_row(workspace_name)
      raise LockNotAcquired, "workspace #{workspace_name} is held by another session" \
        unless row && row.value["terminal_session_id"].to_s == terminal_session_id.to_s

      row
    end

    # Idempotent — deletes the lock row if present.
    def release(workspace_name:)
      @integration.integration_data
                  .where(key: lock_key(workspace_name))
                  .delete_all
    end

    # Release every live lock currently held by the given terminal session,
    # scoped to this integration.
    def release_for_session(terminal_session_id:)
      live_locks
        .where("value ->> 'terminal_session_id' = ?", terminal_session_id.to_s)
        .delete_all
    end

    def live_locks
      @integration.integration_data
                  .with_key_prefix(LOCK_KEY_PREFIX)
                  .live
    end

    def held?(workspace_name:)
      lock_row(workspace_name).present?
    end

    def held_by_session?(workspace_name:, terminal_session_id:)
      row = lock_row(workspace_name)
      row && row.value["terminal_session_id"].to_s == terminal_session_id.to_s
    end

    private

    def lock_row(workspace_name)
      @integration.integration_data
                  .live
                  .find_by(key: lock_key(workspace_name))
    end

    def ttl_minutes
      ttl = @integration.coder_lock_ttl_minutes
      ttl.present? && ttl.positive? ? ttl : 60
    end

    def lock_key(workspace_name)
      "#{LOCK_KEY_PREFIX}#{workspace_name}"
    end
  end
end
