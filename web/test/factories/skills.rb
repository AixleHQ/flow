# frozen_string_literal: true

FactoryBot.define do
  factory :skill do
    sequence(:name) { |n| "skill-#{n}" }
    title { "Skill #{name&.titleize}" }
    content { "Skill content for #{name}" }
    description { "Description for #{name}" }
    kind { :custom }
    scope { nil }  # Default: no scope (requires explicit scope:)

    # == Association Traits ==

    trait :with_company_scope do
      association :scope, factory: :company
    end

    trait :with_project_scope do
      association :scope, factory: :project
    end

    # == Kind Traits ==

    trait :internal do
      kind { :internal }
      scope { nil }
      title { nil }
      content { nil }
    end
  end
end
