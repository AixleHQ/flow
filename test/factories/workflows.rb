# frozen_string_literal: true

FactoryBot.define do
  factory :workflow do
    sequence(:name) { |n| "workflow-#{n}" }
    description { "A test workflow" }
    config { {} }
    # Workflows are Project-scoped (or System for the Aixle Builder, set explicitly).
    scope factory: %i[project standalone]

    trait :with_project_scope do
      scope factory: %i[project standalone]
    end

    trait :system do
      scope_type { "System" }
      scope_id { 0 }
      scope { nil }
    end
  end
end
