# frozen_string_literal: true

FactoryBot.define do
  factory :insights_usage_export do
    terminal_session
    # Mirror the session's company by default, as the exporter will at claim time.
    company { terminal_session&.company }
    state { "pending" }
    attempts { 0 }
    records_sent { 0 }

    trait :exported do
      state { "exported" }
      records_sent { 3 }
      exported_at { Time.current }
    end

    trait :failed do
      state { "failed" }
      error { "collector unavailable" }
      attempts { 1 }
    end

    trait :skipped do
      state { "skipped" }
    end
  end
end
