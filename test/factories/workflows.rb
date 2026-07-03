# frozen_string_literal: true

FactoryBot.define do
  factory :workflow do
    sequence(:name) { |n| "workflow-#{n}" }
    description { "A test workflow" }
    config { {} }
    scope { nil }

    trait :with_company_scope do
      association :scope, factory: :company
    end

    trait :with_project_scope do
      association :scope, factory: :project
    end
  end
end
