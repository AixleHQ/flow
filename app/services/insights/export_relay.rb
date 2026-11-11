# frozen_string_literal: true

module Insights
  # The cron side of the export (docs/design/insights-usage-export.md §6): sends every
  # session still due — one whose inline send never ran, or whose retry time has come.
  class ExportRelay
    DEFAULT_LIMIT = 50

    def self.drain(limit: DEFAULT_LIMIT, now: Time.current, client: Client.build)
      ids = InsightsSessionExport.due(now).order(:id).limit(limit).pluck(:id)
      results = ids.map { |id| Export.deliver(id, client: client, now: now) }
      results.tally.transform_keys(&:to_s).merge("swept" => ids.size)
    end
  end
end
