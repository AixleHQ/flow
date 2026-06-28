# frozen_string_literal: true

FactoryBot.define do
  factory :trigger_event do
    event_type { "slack.message" }
    source { "test" }
    data { {} }
    occurred_at { Time.current }
  end
end
