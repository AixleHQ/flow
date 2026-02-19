# frozen_string_literal: true

FactoryBot.define do
  factory :integration do
    sequence(:name) { |n| "org-#{n}" }
    provider { :github }
    status { :inactive }
    association :company
    association :connected_by, factory: :user

    after(:build) do |integration|
      integration.credentials_data = { installation_id: rand(10_000..99_999).to_s }
    end

    trait :github do
      provider { :github }
    end

    trait :linear do
      provider { :linear }
      after(:build) do |integration|
        integration.credentials_data = { access_token: "lin_api_test_#{SecureRandom.hex(8)}" }
      end
    end

    trait :active do
      status { :active }
    end

    trait :error do
      status { :error }
      settings { { error: "Connection failed" } }
    end
  end
end
