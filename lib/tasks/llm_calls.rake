# frozen_string_literal: true

namespace :llm_calls do
  desc "Materialize llm_calls for finished sessions from usage_statistics.events_data; only adds missing rows"
  task backfill: :environment do
    scope = TerminalSession.where(state: TerminalSession::TERMINAL_STATES)
                           .where(id: UsageStatistic.where("events_data <> '[]'::jsonb").select(:terminal_session_id))
    total = scope.count
    puts "Materializing llm_calls for #{total} sessions..."

    done = 0
    added = 0
    scope.find_each do |session|
      added += LlmCalls::Materializer.call(session)
      done += 1
      print "\r#{done}/#{total}" if (done % 100).zero?
    rescue StandardError => e
      puts "\nSkipping terminal_session #{session.id}: #{e.message}"
    end

    puts "\nDone. #{added} rows added, #{LlmCall.count} llm_calls rows total."
  end
end
