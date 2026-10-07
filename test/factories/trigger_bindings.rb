# frozen_string_literal: true

FactoryBot.define do
  factory :trigger_binding do
    transient do
      # A chat trigger names its messenger; nil leaves it unnamed.
      chat_provider { "slack" }
    end

    project { nil }   # pass explicitly: create(:trigger_binding, project:, workflow:, created_by:)
    workflow { nil }
    created_by factory: :user

    sequence(:name) { |n| "binding-#{n}" }
    event_type { "chat.message" }
    filter_predicate { {} }
    trigger_mode { :auto }
    enabled { true }
    cooldown_seconds { 0 }

    after(:build) do |binding, evaluator|
      filter = binding.filter_predicate.to_h
      if binding.event_type == "chat.message" && evaluator.chat_provider && !filter.key?("provider")
        binding.filter_predicate = { "provider" => evaluator.chat_provider }.merge(filter)
      end
    end
  end
end
