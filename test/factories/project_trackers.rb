# frozen_string_literal: true

FactoryBot.define do
  factory :project_tracker do
    integration { association(:integration, :azure_devops, :active) }
    project { integration.project }
    external_scope_id { integration.azure_project_ids.first }
    name { "Customer Platform" }
    sequence(:handle) { |n| "tracker-#{n}" }

    trait :primary do
      primary { true }
    end

    trait :read_only do
      access { "read_only" }
    end

    trait :detached do
      status { "detached" }
    end
  end
end
