# frozen_string_literal: true

FactoryBot.define do
  factory :tracker_operation do
    project_tracker
    operation { "transition_issue" }
    sequence(:operation_key) { |n| "key-#{n}" }
    request_digest { SecureRandom.hex(32) }
    state { "succeeded" }
  end
end
