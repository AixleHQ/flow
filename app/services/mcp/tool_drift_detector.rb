# frozen_string_literal: true

module MCP
  # Compares what a server declares NOW against what it declared when it was
  # approved, and records the difference.
  #
  # Two entry points, deliberately separate:
  #   * capture — take the baseline (at install, or when a human accepts a change)
  #   * check   — re-probe and record drift without ever moving the baseline
  #
  # `check` never updates the snapshot. That is the whole point: if a re-probe
  # silently became the new baseline, a rug pull would be recorded once and then
  # normalised away on the next run. Only a person accepting the change moves it.
  class ToolDriftDetector
    Outcome = Struct.new(:status, :drift, keyword_init: true) do
      def drifted? = drift.present?
    end

    class << self
      # Establishes the baseline. Failure is non-fatal: an install must not be
      # blocked because a server is briefly unreachable, but the absence of a
      # snapshot has to stay visible rather than being faked as a clean one.
      def capture(server, access_token: nil)
        result = ToolListProbe.call(server: server, access_token: access_token)
        return Outcome.new(status: result.status, drift: {}) unless result.ok?

        server.update!(tool_snapshot: snapshot_for(result.tools), tool_snapshot_at: Time.current, tool_drift: {})
        Outcome.new(status: :ok, drift: {})
      end

      # Re-probes and records what changed. Returns the drift without raising:
      # callers are sweeps, and one hostile or broken server must not stop them.
      def check(server, access_token: nil)
        return Outcome.new(status: :no_baseline, drift: {}) if server.tool_snapshot_at.blank?

        result = ToolListProbe.call(server: server, access_token: access_token)
        return Outcome.new(status: result.status, drift: {}) unless result.ok?

        drift = diff(baseline_tools(server), result.tools)
        if drift.blank?
          # A server that drifted and then reverted is no longer drifted.
          server.update!(tool_drift: {}) if server.tool_drift.present?
          return Outcome.new(status: :ok, drift: {})
        end

        server.update!(tool_drift: drift.merge("detected_at" => Time.current.iso8601))
        Outcome.new(status: :drifted, drift: drift)
      end

      # Accepts the current state as the new baseline — an explicit human act,
      # never something a sweep does on its own.
      def accept(server, access_token: nil)
        capture(server, access_token: access_token)
      end

      private

      def snapshot_for(tools)
        { "tools" => tools, "captured_at" => Time.current.iso8601 }
      end

      def baseline_tools(server)
        Array(server.tool_snapshot["tools"])
      end

      # Added tools matter (new capability the user never approved), removed
      # tools matter (something the project may depend on is gone), and CHANGED
      # ones matter most — a same-named tool whose description moved underneath
      # an approval is exactly the rug-pull shape.
      def diff(before, after)
        by_name_before = before.index_by { |t| t["name"] }
        by_name_after = after.index_by { |t| t["name"] }

        added = by_name_after.keys - by_name_before.keys
        removed = by_name_before.keys - by_name_after.keys
        changed = (by_name_before.keys & by_name_after.keys).select do |name|
          by_name_before[name].slice("description_digest", "schema_digest") !=
            by_name_after[name].slice("description_digest", "schema_digest")
        end

        drift = {}
        drift["added"] = added.sort if added.any?
        drift["removed"] = removed.sort if removed.any?
        drift["changed"] = changed.sort if changed.any?
        drift
      end
    end
  end
end
