# frozen_string_literal: true

# Per-session integrations (docs/design/session-integrations.md §7). Both tasks are idempotent.
namespace :integrations do
  desc "Attach to every project workflow the integrations it gets today (the data migration does this once)"
  task backfill_workflows: :environment do
    puts "workflow links added: #{Integrations::Backfill.new(logger: Logger.new($stdout)).workflows}"
  end

  desc "Give every not ended or suspended session without a set the integrations it gets today. " \
       "SINCE=<time> limits it to sessions created from then on (the second run after a rollout)"
  task backfill_sessions: :environment do
    since = ENV["SINCE"].presence && (Time.zone.parse(ENV["SINCE"]) || abort("SINCE must be an ISO 8601 time"))
    puts "session integration rows added: #{Integrations::Backfill.new(logger: Logger.new($stdout)).sessions(since: since)}"
  end
end
