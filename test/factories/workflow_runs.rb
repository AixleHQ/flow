# frozen_string_literal: true

FactoryBot.define do
  factory :workflow_run do
    workflow factory: %i[workflow with_company_scope]
    project
    user
    state { "pending" }
    mode { "interactive" }
    input_asset_ids { [] }
    shared_context { {} }

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
    end

    trait :cancelled do
      state { "cancelled" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :non_interactive do
      mode { "non_interactive" }
    end

    trait :mixed do
      mode { "mixed" }
    end
  end
end
