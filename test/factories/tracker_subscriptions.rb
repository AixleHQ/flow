# frozen_string_literal: true

FactoryBot.define do
  factory :tracker_subscription do
    integration { association(:integration, :jira, :active) }
    strategy { "manual" }
    status { "active" }
  end
end
