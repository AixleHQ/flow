FactoryBot.define do
  factory :user do
    email
    name
    password { generate :password }
    password_confirmation { password }
    onboarding_completed_at { nil }
    position { nil }
    preferred_agent_language { "en" }
    configured_agents { [] }

    trait :super_admin do
      role { "super_admin" }
      company { nil }
    end

    trait :with_company do
      association :company
    end

    trait :employee do
      role { "employee" }
      association :company
    end

    trait :admin do
      role { "admin" }
      association :company
    end

    trait :onboarding_completed do
      onboarding_completed_at { Time.current }
      position { "dev" }
      preferred_agent_language { "en" }
      configured_agents { %w[claude_code cursor_cli] }
    end

    trait :pending do
      state { "pending" }
    end

    # DEPRECATED: use :employee instead
    trait :collaborator do
      role { "employee" }
      association :company
    end

    # DEPRECATED: use :admin instead
    trait :admin_role do
      role { "admin" }
      association :company
    end

    # DEPRECATED: use :admin instead
    trait :company_admin do
      role { "admin" }
      association :company
    end
  end
end
