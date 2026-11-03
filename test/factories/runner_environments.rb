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
  end
end
