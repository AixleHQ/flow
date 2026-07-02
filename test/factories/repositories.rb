# frozen_string_literal: true

FactoryBot.define do
  factory :repository do
    sequence(:full_name) { |n| "org/repo-#{n}" }
    source_branch { "main" }
    clone_url { "https://github.com/#{full_name}.git" }
    is_private { false }
    description { "Repository #{full_name}" }
    integration
    scope { nil }

    trait :company_scope do
      scope factory: %i[company]
    end

    trait :project_scope do
      scope factory: %i[project]
    end

    trait :private do
      is_private { true }
    end
  end
end
