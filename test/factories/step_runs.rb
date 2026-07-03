# frozen_string_literal: true

FactoryBot.define do
  factory :step_run do
    association :workflow_run
    association :step
    state { "pending" }

    trait :running do
      state { "running" }
      started_at { Time.current }
    end

    trait :completed do
      state { "completed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :failed do
      state { "failed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      error_message { "Step execution failed" }
    end

    trait :skipped do
      state { "skipped" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      skip_reason { "Manually skipped" }
    end

    trait :with_terminal_session do
      association :terminal_session
    end
  end
end
