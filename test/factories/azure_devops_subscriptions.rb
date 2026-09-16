# frozen_string_literal: true

FactoryBot.define do
  factory :azure_devops_subscription do
    integration factory: %i[integration azure_devops active]
    event_type { "build.complete" }
    status { :active }
    azure_subscription_id { SecureRandom.uuid }

    transient do
      # Explicit so a test can assert the exact value it authenticates with;
      # the model generates one when nothing is given.
      webhook_password { "hook-secret" }
    end

    after(:build) do |subscription, evaluator|
      subscription.password = evaluator.webhook_password
    end

    trait :pull_request_merged do
      event_type { "git.pullrequest.merged" }
    end

    trait :probation do
      status { :probation }
    end
  end
end
