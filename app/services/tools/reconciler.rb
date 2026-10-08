# frozen_string_literal: true

module Tools
  # Projects the code registry into `tools` shadow rows (Solid Queue's
  # recurring-task mirror pattern) so every existing FK — tool_results.tool_id,
  # session_tools.tool_id, steps.tool_ids jsonb — keeps working unchanged while
  # the code stays the single source of truth for definitions.
  #
  # Rows with source: "code" are owned by this reconciler; humans never write
  # them. Diff-based: steady-state runs are write-free. Removed platform tools
  # are only ever soft-deleted (tool_results has a RESTRICT FK; history must
  # survive). `enabled` is set on insert and on revival only, so a manual admin
  # disable survives reconciles, matching the old seeds behavior.
  #
  # Runs: on deploy (platform_tools:seed rake), at boot (self-heal, try-lock so
  # N-1 processes of a rolling restart no-op — see tools_registry initializer),
  # and lazily via Tool.shadow_for when a row is needed before either happened
  # (materialize!, which never retires a row).
  class Reconciler
    LOCK_KEY = "aixle_tools_reconcile"

    class << self
      def run!
        with_guards { reconcile(blocking: true, retire: true) }
      end

      # During a rolling deploy an old process lands here for a name the new
      # release renamed away. The rows it does not know belong to that newer
      # release, so this path creates and converges rows but never retires one.
      def materialize!
        with_guards { reconcile(blocking: true, retire: false) }
      end

      # Boot-time variant: skips (rather than waits) when another process
      # holds the lock, and never raises — a drifted registry must not become
      # a crash-looping deploy.
      def run_if_needed!
        with_guards { reconcile(blocking: false, retire: true) }
      rescue StandardError => e
        Rails.logger.error("[Tools::Reconciler] boot reconcile skipped: #{e.class}: #{e.message}")
        false
      end

      private

      def with_guards
        return false unless Tool.table_exists? && Tool.column_names.include?("source")
        return false if migrations_pending?

        yield
      end

      def migrations_pending?
        ActiveRecord::Migration.check_all_pending!
        false
      rescue ActiveRecord::PendingMigrationError
        true
      end

      def reconcile(blocking:, retire:)
        Tool.transaction do
          return false unless acquire_lock(blocking: blocking)

          existing = Tool.where(source: "code").index_by(&:name)
          upsert_definitions(existing)
          soft_delete_stale(existing) if retire
        end
        true
      end

      def acquire_lock(blocking:)
        key = Tool.connection.quote(LOCK_KEY)
        if blocking
          Tool.connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{key}))")
          true
        else
          result = Tool.connection.select_value("SELECT pg_try_advisory_xact_lock(hashtext(#{key}))")
          ActiveModel::Type::Boolean.new.cast(result)
        end
      end

      def upsert_definitions(existing)
        Registry.definitions.each_value do |definition|
          # :user-audience tools are served straight from the registry by the
          # personal MCP server — no session attachment, no ToolResult FK, so
          # no shadow row to maintain.
          next unless definition.audience == :session

          desired = definition.to_row_attributes
          row = existing[definition.name]

          row.nil? ? create_row(desired) : converge(row, desired)
        end
      end

      def create_row(desired)
        Tool.create!(desired.merge(enabled: true))
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Raced by another process (partial unique index on name where
        # source='code'); their row is as good as ours.
        Tool.find_by!(source: "code", name: desired[:name]).tap { |row| converge(row, desired) }
      end

      # A retired row is disabled by its retirement (soft_delete_stale), not by
      # an admin, so bringing it back re-enables it.
      def converge(row, desired)
        return unless drifted?(row, desired)

        row.update!(row.deleted? ? desired.merge(enabled: true) : desired)
      end

      def drifted?(row, desired)
        desired.any? do |attr, value|
          current = row.public_send(attr)
          if attr == :input_schema
            current.as_json != value.as_json
          else
            # Enumerize values (kind, execution_mode) compare via to_s.
            current.respond_to?(:to_s) && value.is_a?(String) ? current.to_s != value : current != value
          end
        end
      end

      def soft_delete_stale(existing)
        stale = existing.values.select do |row|
          defn = Registry.fetch(row.name)
          row.deleted_at.nil? && (defn.nil? || defn.audience != :session)
        end
        stale.each { |row| row.update!(deleted_at: Time.current, enabled: false) }
      end
    end
  end
end
