# frozen_string_literal: true

FactoryBot.define do
  factory :company do
    name
    email_domain
    auto_accept_users { false }
    # Like a company an operator made: past the free allowance with nothing
    # capping it, and its domain taken as proved. Either default the other way
    # would quietly change behaviour across every suite that has nothing to do
    # with billing or with joining.
    billing_state { "active" }
    domain_verified_at { Time.current }

    trait :auto_accept do
      auto_accept_users { true }
    end

    trait :trialing do
      billing_state { "trialing" }
    end

    trait :billing_blocked do
      billing_state { "blocked" }
    end

    trait :domain_unverified do
      domain_verified_at { nil }
    end
  end
end
