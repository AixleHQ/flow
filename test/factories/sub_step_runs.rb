# frozen_string_literal: true

FactoryBot.define do
  factory :sub_step_run do
    step_run
    sub_step
    state { "pending" }

    trait :in_progress do
      state { "in_progress" }
      started_at { Time.current }
    end

    trait :completed do
      state { "completed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end
  end
end
