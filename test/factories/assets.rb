# frozen_string_literal: true

FactoryBot.define do
  factory :asset do
    sequence(:name) { |n| "asset-#{n}.md" }
    scope { nil }
    created_by factory: %i[user]

    trait :with_company_scope do
      scope factory: %i[company]
    end

    trait :with_project_scope do
      scope factory: %i[project]
    end

    trait :public_asset do
      public { true }
      public_token { SecureRandom.urlsafe_base64(16) }
    end
  end
end
