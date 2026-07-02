# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name
    password { generate(:password) }
    password_confirmation { password }
    onboarding_state { "step1" }
    position { nil }
    preferred_agent_language { "en" }
    super_admin { false }

    # Company/role now live on CompanyMembership. Pass a transient `company:`
    # (or use a role trait) to get an active membership created after :create.
    transient do
      email_sequence { SecureRandom.hex(4) }
      company { nil }
      membership_role { nil }
      membership_state { "active" }
    end

    # Generate email based on the (transient) company domain if present
    email do
      if company.present?
        "user-#{email_sequence}@#{company.email_domain}"
      else
        "user-#{email_sequence}@example.com"
      end
    end

    after(:create) do |user, evaluator|
      next if user.super_admin?
      next if evaluator.company.blank? && evaluator.membership_role.blank?

      create(
        :company_membership,
        user: user,
        company: evaluator.company || create(:company),
        role: evaluator.membership_role || "employee",
        state: evaluator.membership_state
      )
    end

    # == Association Traits ==

    trait :with_company do
      company { association(:company) }
    end

    # == Role Traits (membership-level; super_admin is platform-level) ==

    trait :super_admin do
      super_admin { true }
    end

    trait :employee do
      membership_role { "employee" }
    end

    trait :admin do
      membership_role { "admin" }
    end

    trait :viewer do
      membership_role { "viewer" }
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
      membership_state { "invited" }
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
