# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_skill do
    sequence(:slug) { |n| "catalog-skill-#{n}" }
    source { "test-org/skills" }
    registry_id { "#{source}/#{slug}" }
    title { nil }
    description { "Description for #{slug}" }
    installs { 0 }
    install_count { 0 }
    featured { false }
    bulk_publisher { false }
    registry_synced_at { Time.current }

    trait :featured do
      featured { true }
    end

    # A source shipping a whole collection, e.g. `larksuite/cli`.
    trait :bulk do
      bulk_publisher { true }
    end
  end
end
