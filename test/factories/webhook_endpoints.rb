# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_endpoint do
    sequence(:slug) { |n| "endpoint-#{n}" }
    provider { :slack }
    verification_strategy { :slack_v0 }
    secret { "signing-secret" }
    enabled { true }
    project { nil }

    trait :generic do
      provider { :generic }
      verification_strategy { :none }
      secret { nil }
    end
  end
end
