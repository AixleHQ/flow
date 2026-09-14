# frozen_string_literal: true

FactoryBot.define do
  factory :azure_devops_installation do
    company
    sequence(:organization_slug) { |n| "contoso-#{n}" }
    tenant_id { SecureRandom.uuid }
    client_id { SecureRandom.uuid }
    app_config_key { "default" }
    status { :inactive }
    # Empty means NO projects are reachable — never "all" — so a test that wants
    # a usable installation has to say which project it approved.
    allowed_project_ids { [] }

    trait :active do
      status { :active }
      last_verified_at { Time.current }
    end

    trait :approved do
      approved_by factory: %i[user]
      approved_at { Time.current }
    end

    transient do
      azure_project_id { nil }
    end

    trait :with_project do
      allowed_project_ids { [ SecureRandom.uuid ] }
    end
  end
end
