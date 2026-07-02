# frozen_string_literal: true

FactoryBot.define do
  factory :integration do
    sequence(:name) { |n| "org-#{n}" }
    provider { :github }
    status { :inactive }
    company
    connected_by factory: %i[user]

    after(:build) do |integration|
      integration.credentials_data = { installation_id: rand(10_000..99_999).to_s }
    end

    trait :github do
      provider { :github }
    end

    trait :gitlab do
      provider { :gitlab }
      after(:build) do |integration|
        integration.credentials_data = { personal_access_token: "glpat-test_#{SecureRandom.hex(8)}" }
      end
    end

    trait :linear do
      provider { :linear }
      after(:build) do |integration|
        integration.credentials_data = { access_token: "lin_api_test_#{SecureRandom.hex(8)}" }
      end
    end

    trait :coder do
      provider { :coder }
      after(:build) do |integration|
        integration.credentials_data = {
          coder_url: "https://coder.example.com",
          session_token: "coder-test-#{SecureRandom.hex(8)}",
          user_id: SecureRandom.uuid
        }
        integration.settings = {
          coder_username:   "test-user",
          coder_user_email: "test@example.com",
          lock_ttl_minutes: 60
        }
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
