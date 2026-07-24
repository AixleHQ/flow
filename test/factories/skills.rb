# frozen_string_literal: true

FactoryBot.define do
  factory :skill do
    sequence(:name) { |n| "skill-#{n}" }
    title { "Skill #{name&.titleize}" }
    content { "Skill content for #{name}" }
    description { "Description for #{name}" }
    package { |s| "test-org/skills@#{s.name}" }
    source { "test-org/skills" }
    source_url { "https://github.com/test-org/skills" }
    install_count { 0 }
    # Skills are Project-scoped only.
    scope factory: %i[project standalone]

    trait :with_project_scope do
      scope factory: %i[project standalone]
    end
  end
end
