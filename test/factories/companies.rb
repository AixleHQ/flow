# frozen_string_literal: true

FactoryBot.define do
  factory :company do
    name
    email_domain
    auto_accept_users { false }

    trait :auto_accept do
      auto_accept_users { true }
    end
  end
end
