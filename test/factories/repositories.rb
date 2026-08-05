# frozen_string_literal: true

FactoryBot.define do
  factory :repository do
    sequence(:full_name) { |n| "org/repo-#{n}" }
    source_branch { "main" }
    clone_url { "https://github.com/#{full_name}.git" }
    is_private { false }
    description { "Repository #{full_name}" }
    integration
    # Repositories are Project-scoped only.
    scope factory: %i[project standalone]

    trait :project_scope do
      scope factory: %i[project standalone]
    end

    trait :private do
      is_private { true }
    end

    # Attached without an integration: cloned anonymously, read-only.
    trait :public_source do
      integration { nil }
    end
  end
end
