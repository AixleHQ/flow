# frozen_string_literal: true

FactoryBot.define do
  factory :repository do
    sequence(:full_name) { |n| "org/repo-#{n}" }
    source_branch { "main" }
    clone_url { "https://github.com/#{full_name}.git" }
    is_private { false }
    description { "Repository #{full_name}" }
    association :integration
    scope { nil }

    trait :company_scope do
      association :scope, factory: :company
    end

    trait :project_scope do
      association :scope, factory: :project
    end

    trait :private do
      is_private { true }
    end
  end
end
