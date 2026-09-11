# frozen_string_literal: true

FactoryBot.define do
  factory :folder do
    sequence(:path) { |n| "folder-#{n}" }
    scope { nil }
    created_by factory: %i[user]

    trait :with_company_scope do
      scope factory: %i[company]
    end

    trait :with_project_scope do
      scope factory: %i[project]
    end
  end
end
