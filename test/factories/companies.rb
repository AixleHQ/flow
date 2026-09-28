# frozen_string_literal: true

FactoryBot.define do
  factory :company do
    name
    email_domain
    auto_accept_users { false }
    # Like a company an operator made: past the free allowance, nothing capping
    # it. A factory default of "trialing" would cap every company in every suite
    # to one session, and only on an installation running as saas.
    billing_state { "active" }

    trait :auto_accept do
      auto_accept_users { true }
    end

    trait :trialing do
      billing_state { "trialing" }
    end

    trait :billing_blocked do
      billing_state { "blocked" }
    end
  end
end
