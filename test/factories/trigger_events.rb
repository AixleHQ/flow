# frozen_string_literal: true

FactoryBot.define do
  factory :trigger_event do
    event_type { "slack.message" }
    # A chat event counts only from its provider's own receiver (Chat.provider_for).
    source { event_type.to_s.start_with?("slack.") ? "slack:test" : "test" }
    data { {} }
    occurred_at { Time.current }
  end
end
