# frozen_string_literal: true

namespace :llm_calls do
  desc "Backfill llm_calls rows from existing usage_statistics.events_data"
  task backfill: :environment do
    scope = UsageStatistic.where("events_data != '[]'::jsonb AND events_data IS NOT NULL")
    total = scope.count
    puts "Backfilling llm_calls for #{total} usage_statistics records..."

    done = 0
    scope.find_each do |stat|
      stat.terminal_session&.send(:materialize_llm_calls)
      done += 1
      print "\r#{done}/#{total}" if (done % 100).zero?
    rescue StandardError => e
      puts "\nSkipping terminal_session #{stat.terminal_session_id}: #{e.message}"
    end

    puts "\nDone. #{LlmCall.count} llm_calls rows total."
  end
end
