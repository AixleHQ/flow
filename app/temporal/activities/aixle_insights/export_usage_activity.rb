# frozen_string_literal: true

module Activities
  module AixleInsights
    # Sends completed agent-session usage to each connected company's Insights
    # org and replays the ledger (see AixleInsights::UsageExporter).
    #
    # Single attempt on purpose (see the workflow): recovery is the next
    # scheduled run replaying `unsent` ledger rows, not a Temporal retry. The
    # exporter self-gates on Settings.aixle_insights.enabled, so this is safe to
    # call unconditionally — a disabled deployment just gets a no-op summary.
    class ExportUsageActivity < ::Activities::Base
      def run(_input = nil)
        ::AixleInsights::UsageExporter.new.call
      end
    end
  end
end
