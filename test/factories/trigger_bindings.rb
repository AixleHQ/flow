# frozen_string_literal: true

FactoryBot.define do
  factory :trigger_binding do
    project { nil }   # pass explicitly: create(:trigger_binding, project:, workflow:, created_by:)
    workflow { nil }
    created_by factory: :user

    sequence(:name) { |n| "binding-#{n}" }
    event_type { "slack.message" }
    filter_predicate { {} }
    trigger_mode { :auto }
    enabled { true }
    cooldown_seconds { 0 }
  end
end
