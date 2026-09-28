# frozen_string_literal: true

FactoryBot.define do
  factory :user_identity do
    user
    identity_provider
    sequence(:subject) { |n| "subject-#{n}" }
    email { user.email }
    email_verified { true }
  end
end
