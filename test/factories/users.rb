# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name
    password { generate :password }
    password_confirmation { password }
    onboarding_state { "step1" }
    position { nil }
    preferred_agent_language { "en" }
    company { nil }  # Default: no company (requires :with_company trait or explicit company:)
    role { "employee" }

    # Generate email based on company domain if company exists, otherwise use example.com
    transient do
      email_sequence { SecureRandom.hex(4) }
    end

    email do
      if company.present?
        "user-#{email_sequence}@#{company.email_domain}"
      else
        "user-#{email_sequence}@example.com"
      end
    end

    # == Association Traits ==

    trait :with_company do
      association :company
    end

    # == Role Traits ==

    trait :super_admin do
      role { "super_admin" }
      company { nil }
    end

    trait :employee do
      role { "employee" }
    end

    trait :admin do
      role { "admin" }
    end

    trait :viewer do
      role { "viewer" }
    end

    # == State Traits ==

    trait :onboarding_completed do
      onboarding_state { "completed" }
      onboarding_completed_at { Time.current }
      position { "dev" }
      preferred_agent_language { "en" }
    end

    trait :pending do
      state { "pending" }
    end

    # == Nested Associations ==

    trait :with_agent_credential do
      transient do
        agent_type { "claude_code" }
      end

      after(:create) do |user, evaluator|
        create(:agent_credential, user: user, agent_type: evaluator.agent_type)
      end
    end
  end
end
