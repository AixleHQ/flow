# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_credential do
    association :owner, factory: :user
    oauth_client
    provider { "sentry" }
    status { :active }
    expires_at { 8.hours.from_now }

    after(:build) do |credential|
      credential.access_token ||= "at-#{SecureRandom.hex(6)}"
      credential.refresh_token ||= "rt-#{SecureRandom.hex(6)}"
    end

    # A user's own GitHub connection (docs/design/github-user-identity.md §3.3).
    trait :github_user do
      provider { "github" }
      metadata { { "github_user" => { "id" => 123, "login" => "octo-user", "name" => "Octo User",
                                        "avatar_url" => "https://a.test/123", "fetched_at" => Time.current.iso8601 } } }
    end
  end
end
