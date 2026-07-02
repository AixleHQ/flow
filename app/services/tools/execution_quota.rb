# frozen_string_literal: true

module Tools
  # Per-company cap on concurrently running container tool executions —
  # multi-tenant fairness at the dispatch boundary (Temporal has no built-in
  # per-tenant concurrency limit). Checked under a per-company advisory lock
  # so concurrent dispatches can't leak past the cap. At capacity the agent
  # gets a fast structured error (agents degrade badly on unbounded queueing)
  # rather than a parked execution. Off by default (0) — opt in by setting
  # AIXLE_MAX_CONCURRENT_TOOL_EXECUTIONS_PER_COMPANY.
  module ExecutionQuota
    DEFAULT_LIMIT = 0

    class << self
      # Yields inside the lock when a slot is free; returns the at-capacity
      # error result otherwise.
      def with_slot(company)
        cap = limit
        return yield if cap.zero? || company.nil?

        ToolResult.transaction do
          acquire_lock(company)
          running = running_count(company)
          return at_capacity_result(running, cap) if running >= cap

          yield
        end
      end

      def limit
        ENV.fetch("AIXLE_MAX_CONCURRENT_TOOL_EXECUTIONS_PER_COMPANY", DEFAULT_LIMIT).to_i
      end

      private

      def acquire_lock(company)
        key = ToolResult.connection.quote("aixle_tool_quota_#{company.id}")
        ToolResult.connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{key}))")
      end

      def running_count(company)
        ToolResult.where(state: "processing")
                  .joins(terminal_session: :project)
                  .where(projects: { company_id: company.id })
                  .count
      end

      def at_capacity_result(running, cap)
        {
          exit_code: 1,
          stdout: "",
          stderr: "Tool execution capacity reached for this workspace " \
                  "(#{running}/#{cap} running). Wait for a running execution " \
                  "to finish and retry."
        }
      end
    end
  end
end
