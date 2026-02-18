# frozen_string_literal: true

FactoryBot.define do
  factory :asset do
    sequence(:name) { |n| "asset-#{n}.md" }
    asset_type { :document }
    scope { nil }
    association :created_by, factory: :user

    trait :with_company_scope do
      association :scope, factory: :company
    end

    trait :with_project_scope do
      association :scope, factory: :project
    end

    trait :public_asset do
      public { true }
      public_token { SecureRandom.urlsafe_base64(16) }
    end
  end
end
