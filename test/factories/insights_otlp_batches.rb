# frozen_string_literal: true

FactoryBot.define do
  # One OTLP request in the Insights outbox, as the relay writes it (already enriched).
  factory :insights_otlp_batch do
    integration
    project
    terminal_session
    signal { "logs" }
    record_count { 1 }
    payload do
      InsightsOtlpBatch.wrap("resourceLogs" => [ { "resource" => { "attributes" => [] },
                                                   "scopeLogs" => [ { "logRecords" => [ { "timeUnixNano" => "1" } ] } ] } ])
    end
  end
end
