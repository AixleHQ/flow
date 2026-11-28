# frozen_string_literal: true

FactoryBot.define do
  # A `manual` machine as POST /runner/v1/register leaves it.
  factory :runner_environment do
    runner
    company { runner.company }
    sequence(:key) { |n| "aixle-env-#{n}" }
    sequence(:display_name) { |n| "machine-#{n}" }
    origin { :registered }
    state { :registered }
    last_heartbeat_at { Time.current }

    # An environment the platform created for a session (runner-coder.md §6), of a
    # `coder` runner: `provisioning`, never heard, with no display name until its
    # machine registers into it. Give `state:` for another.
    trait :allocated do
      runner { association(:runner, :coder) }
      sequence(:key) { |n| "coder-#{n.to_s.rjust(8, '0')}" }
      display_name { nil }
      origin { :allocated }
      state { :provisioning }
      last_heartbeat_at { nil }
    end
  end
end
