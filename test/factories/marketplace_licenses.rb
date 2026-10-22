# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_license do
    sequence(:license_arn) { |n| "arn:aws:license-manager:us-east-1:444455556666:license/l-#{n}" }
    customer_aws_account_id { "444455556666" }
    product_code { "saasproduct0000000000000" }
    sequence(:agreement_id) { |n| "agmt-#{n}" }
    # A subscription AWS has confirmed and nobody has registered against yet,
    # which is the state a licence first exists in.
    subscription_state { "pending" }

    trait :active do
      subscription_state { "active" }
      subscribed_at { Time.current }
    end

    trait :ending do
      subscription_state { "ending" }
      subscribed_at { 30.days.ago }
    end

    trait :ended do
      subscription_state { "ended" }
      subscribed_at { 30.days.ago }
      ended_at { Time.current }
    end

    trait :bound do
      company
    end

    trait :free_trial do
      registered_offer_type { "free-trial" }
    end
  end
end
