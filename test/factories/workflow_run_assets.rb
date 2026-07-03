# frozen_string_literal: true

FactoryBot.define do
  factory :workflow_run_asset do
    workflow_run
    sequence(:name) { |n| "output-#{n}.md" }
    content_type { "text/markdown" }
    file_size { 1024 }

    trait :with_step_run do
      produced_by_step_run factory: %i[step_run]
    end
  end
end
