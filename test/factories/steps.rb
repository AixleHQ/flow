# frozen_string_literal: true

FactoryBot.define do
  factory :step do
    association :workflow
    sequence(:name) { |n| "Step #{n}" }
    sequence(:position) { |n| n }
    description { "A test step" }
    instructions { "Do the thing" }
    allow_non_interactive { false }
    skip_policy { :never }
    on_failure { :fail }
    max_retries { 0 }
    input_asset_specs { [] }
    output_asset_specs { [] }
    tool_ids { [] }
    agent { nil }

    trait :with_agent do
      association :agent
    end

    trait :non_interactive do
      allow_non_interactive { true }
    end
  end
end
