# frozen_string_literal: true

FactoryBot.define do
  factory :company_membership do
    user
    company
    role { "employee" }
    state { "active" }

    # == Role Traits ==

    trait :admin do
      role { "admin" }
    end

    trait :viewer do
      role { "viewer" }
    end

    # == State Traits ==

    trait :invited do
      state { "invited" }
      invited_at { Time.current }
    end

    trait :suspended do
      state { "suspended" }
    end

    trait :revoked do
      state { "revoked" }
    end
  end
end
