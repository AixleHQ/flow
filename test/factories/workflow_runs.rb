# frozen_string_literal: true

FactoryBot.define do
  factory :workflow_run do
    workflow factory: %i[workflow with_project_scope]
    # Keep run/workflow/user in one company by default so a bare create is valid.
    project { workflow.scope }
    user { association(:user, company: project.company) }
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
