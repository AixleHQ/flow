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
  # Ownership is a `Holder` (N2 / DD-13). A session holder is recorded as
  # `terminal_session_id` in the lock value, and the teardown hook in
  # `WorkflowStepStrategy` releases by session id when the step ends. An
  # environment holder (a runner's environment) is recorded as
  # `runner_environment_id` and its hold is explicit: `expires_at` is NULL, so
  # expiry never reclaims it, `touch` has nothing to renew and
  # `release_all_for_session` never releases it. It ends through
  # `release_owned` only.
  class LockService
    LOCK_KEY_PREFIX = "coder:workspace_lock:"

    # Who holds a workspace. `kind` decides the lock value's key and whether
    # the hold expires, so a caller cannot ask for the wrong one.
    HOLDER_VALUE_KEYS = { session: "terminal_session_id", environment: "runner_environment_id" }.freeze

    Holder = Data.define(:kind, :id) do
      def self.session(id)     = new(kind: :session, id: id)
      def self.environment(id) = new(kind: :environment, id: id)

      def initialize(kind:, id:)
        kind = kind.to_sym
        raise ArgumentError, "unknown holder kind #{kind.inspect}" unless HOLDER_VALUE_KEYS.key?(kind)
        raise ArgumentError, "a holder needs an id" if id.to_s.empty?

        super(kind: kind, id: id.to_s)
      end

      def session?     = kind == :session
      def environment? = kind == :environment

      # An environment holder's hold has no expiry and no renewal.
      def explicit? = environment?

      # The key of the holder's id inside the lock value.
      def value_key = HOLDER_VALUE_KEYS.fetch(kind)
    end

    # The workspace a holder holds, as the lock row records it.
    Hold = Data.define(:workspace_name, :workspace_id, :expires_at)

    class LockNotAcquired < StandardError; end

    # Release every Coder workspace lock held by the given terminal session
    # (session holders only: an environment holder's hold is never released
    # because a terminal session ended),
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
        new(integration).release_for_session(holder: Holder.session(session.id))
      rescue StandardError => e
        Rails.logger.warn("[Coder::LockService] release for integration #{integration.id} failed: #{e.message}")
      end
    end

    def initialize(integration)
      @integration = integration
    end

    # Atomic acquire. Returns the `IntegrationData` row on success, raises
    # `LockNotAcquired` if another live lock already holds the workspace.
    #
    # The workspace id is unique across every integration's live locks (see
    # MakeCoderWorkspaceLocksExclusive): a pool reached through two integrations
    # is still one set of machines. Another integration's EXPIRED lock on the same
    # box is cleared first, since the reclaim below only sees this integration's.
    def acquire(workspace_name:, workspace_id:, holder:,
                note: nil, acquired_by: nil)
      now        = Time.current
      clear_expired_locks_elsewhere(workspace_id, now)
      expires_at = holder.explicit? ? nil : now + ttl_minutes.minutes
      payload    = {
        kind:                "workspace_lock",
        workspace_id:        workspace_id.to_s,
        holder.value_key => holder.id,
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
      begin
        ActiveRecord::Base.connection.execute(sql)
      rescue ActiveRecord::RecordNotUnique
        raise LockNotAcquired, "workspace #{workspace_name} is held through another integration"
      end

      row = lock_row(workspace_name)
      raise LockNotAcquired, "workspace #{workspace_name} is held by another session" \
        unless row && owned_by?(row, holder)

      row
    end

    # Push the lock's expiry forward, holder-scoped. Called on every tool use
    # against the workspace, which turns the TTL from "time since the lock was
    # taken" into "time since the session last did anything" — the property the
    # pool actually needs. A step that dies hard frees its box after one idle
    # TTL instead of holding it for the full window from acquisition, while a
    # long-running gate never has its lock expire underneath it.
    #
    # Single statement, scoped to the holder, so a lock that expired mid-flight
    # and was reclaimed by another session is left alone. Returns whether a row
    # was renewed.
    #
    # An explicit hold has no expiry to push: it is reported as renewed while
    # the holder still holds it, and its row is left as it is.
    def touch(workspace_name:, holder:)
      now = Time.current
      scope = holder_rows(holder).where(key: lock_key(workspace_name))
      return scope.exists? if holder.explicit?

      scope.update_all([ "expires_at = ?, updated_at = ?", now + ttl_minutes.minutes, now ])
           .positive?
    end

    # Idempotent — deletes the lock row if present. Not scoped to a holder:
    # callers that act on behalf of a session must use `release_owned`.
    def release(workspace_name:)
      @integration.integration_data
                  .where(key: lock_key(workspace_name))
                  .delete_all
    end

    # Holder-scoped release. Deletes the row only while `holder`
    # still owns it, in a single statement — so a lock that expired mid-flight
    # and was reclaimed by another session is left alone (a read-then-delete
    # pair would race that reclaim). Returns whether a row was deleted.
    def release_owned(workspace_name:, holder:)
      holder_rows(holder).where(key: lock_key(workspace_name))
                         .delete_all
                         .positive?
    end

    # Release every live lock currently held by the given holder, scoped to
    # this integration.
    def release_for_session(holder:)
      holder_rows(holder).live.delete_all
    end

    def live_locks
      @integration.integration_data
                  .with_key_prefix(LOCK_KEY_PREFIX)
                  .live
    end

    def held?(workspace_name:)
      lock_row(workspace_name).present?
    end

    def held_by_session?(workspace_name:, holder:)
      row = lock_row(workspace_name)
      row.present? && owned_by?(row, holder)
    end

    # The workspace `holder` holds, or nil. A holder that holds several (a
    # session may) gets the oldest. Lets `Allocator#allocate` be idempotent for
    # a holder, and `Allocator#delete` find a workspace whose name nobody wrote
    # down.
    def held_by(holder:)
      row = holder_rows(holder).live.order(:created_at, :id).first
      return nil unless row

      Hold.new(
        workspace_name: row.key.delete_prefix(LOCK_KEY_PREFIX),
        workspace_id:   row.value["workspace_id"].to_s,
        expires_at:     row.expires_at
      )
    end

    private

    def owned_by?(row, holder)
      row.value[holder.value_key].to_s == holder.id
    end

    # The integration's lock rows, expired or not, that `holder` owns. One
    # predicate, so the ownership rule is written once. `value_key` is one of
    # two constants, never caller input.
    def holder_rows(holder)
      @integration.integration_data
                  .with_key_prefix(LOCK_KEY_PREFIX)
                  .where("value ->> '#{holder.value_key}' = ?", holder.id)
    end

    def clear_expired_locks_elsewhere(workspace_id, now)
      return if workspace_id.blank?

      IntegrationData.with_key_prefix(LOCK_KEY_PREFIX)
                     .where.not(integration_id: @integration.id)
                     .where("value ->> 'workspace_id' = ?", workspace_id.to_s)
                     .where("expires_at IS NOT NULL AND expires_at <= ?", now)
                     .delete_all
    end

    def lock_row(workspace_name)
      @integration.integration_data
                  .live
                  .find_by(key: lock_key(workspace_name))
    end

    def ttl_minutes
      ttl = @integration.coder_lock_ttl_minutes
      ttl.present? && ttl.positive? ? ttl : 120
    end

    def lock_key(workspace_name)
      "#{LOCK_KEY_PREFIX}#{workspace_name}"
    end
  end
end
