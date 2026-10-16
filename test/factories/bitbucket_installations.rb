# frozen_string_literal: true

FactoryBot.define do
  # A live installation of the Aixle Flow Forge app, unbound until a pairing is
  # confirmed — `:bound` gives it a company, `:with_token` a token with two hours
  # left, the way a heartbeat tick leaves it.
  factory :bitbucket_installation do
    sequence(:forge_installation_id) { |n| "ari:cloud:ecosystem::installation/#{SecureRandom.uuid}-#{n}" }
    forge_environment_id { BitbucketTestHelper::FORGE_ENVIRONMENT_ID }
    workspace_uuid { "{#{SecureRandom.uuid}}" }
    sequence(:workspace_slug) { |n| "acme-#{n}" }
    workspace_name { "Acme" }
    status { :active }
    last_invocation_at { Time.current }

    trait :bound do
      company
      bound_at { Time.current }
    end

    trait :with_token do
      after(:create) do |installation|
        installation.store_token!("forge-system-token-#{SecureRandom.hex(8)}", expires_at: 2.hours.from_now)
      end
    end
  end
end
