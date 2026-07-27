# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name
    password { generate(:password) }
    password_confirmation { password }
    super_admin { false }

    # Company, role AND onboarding all live on CompanyMembership now — onboarding
    # is per company (different role, different agents, a separate agent
    # credential for billing). Pass a transient `company:` (or a role trait) to
    # get a membership created after :create; the onboarding transients below
    # land on that membership, not on the user.
    transient do
      email_sequence { SecureRandom.hex(4) }
      company { nil }
      membership_role { nil }
      membership_state { "active" }
      onboarding_state { "step1" }
      onboarding_completed_at { nil }
      position { nil }
      preferred_agent_language { "en" }
      selected_agents { [] }
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
        state: evaluator.membership_state,
        onboarding_state: evaluator.onboarding_state,
        onboarding_completed_at: evaluator.onboarding_completed_at,
        position: evaluator.position,
        preferred_agent_language: evaluator.preferred_agent_language,
        selected_agents: evaluator.selected_agents
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

    # Onboarding completion is a property of the MEMBERSHIP. Using this trait
    # without a company therefore has nothing to mark complete — pass `company:`
    # or combine with a role trait.
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

    # The credential belongs to a (user, company) pair, so it needs the same
    # company the membership was created in.
    trait :with_agent_credential do
      transient do
        agent_type { "claude_code" }
      end

      after(:create) do |user, evaluator|
        company = user.company_memberships.first&.company || evaluator.company
        next if company.nil?

        create(:agent_credential, user: user, company: company, agent_type: evaluator.agent_type)
      end
    end
  end
end
