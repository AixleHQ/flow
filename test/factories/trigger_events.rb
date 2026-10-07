# frozen_string_literal: true

FactoryBot.define do
  factory :trigger_event do
    transient do
      chat_provider { "slack" }
    end

    event_type { "chat.message" }
    # A chat event counts only from its provider's own receiver (Chat.provider_for).
    source { event_type.to_s == "chat.message" && chat_provider ? "#{chat_provider}:test" : "test" }
    data { {} }
    occurred_at { Time.current }

    after(:build) do |event, evaluator|
      data = event.data.to_h
      if event.event_type == "chat.message" && evaluator.chat_provider && !data.key?("provider")
        event.data = { "provider" => evaluator.chat_provider }.merge(data)
      end
    end
  end
end
