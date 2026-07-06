# frozen_string_literal: true

FactoryBot.define do
  factory :config_item do
    sequence(:name) { |n| "CONFIG_VAR_#{n}" }
    value { "test_value" }
    description { "Test config item" }
    item_type { :variable }
    scope { nil }  # Default: no scope (requires explicit scope:)

    # == Association Traits ==

    trait :with_company_scope do
      scope factory: %i[company]
    end

    trait :with_project_scope do
      scope factory: %i[project]
    end

    # Note: For most tests, pass scope: explicitly:
    #   create(:config_item, scope: company)
    #   create(:config_item, scope: project)

    # == Type Traits ==

    trait :secret do
      item_type { :secret }
      value { "secret_value" }
    end

    trait :variable do
      item_type { :variable }
      value { "plain_text_value" }
      encrypted_value { nil }
    end
  end
end
