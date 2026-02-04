# frozen_string_literal: true

FactoryBot.define do
  factory :tool do
    sequence(:name) { |n| "tool_#{n}" }
    display_name { name.titleize }
    docker_image { "alpine:latest" }
    enabled { true }
    required_config_items { [] }
    input_schema { {} }
    kind { :custom }
    scope { nil }  # Default: no scope (requires explicit scope:)

    # == Association Traits ==

    trait :with_company_scope do
      association :scope, factory: :company
    end

    trait :with_project_scope do
      association :scope, factory: :project
    end

    # Alias for backward compatibility
    trait :project do
      # Expects scope: to be passed explicitly
      # This trait is just a semantic marker for project-scoped tools
    end

    # Note: For most tests, pass scope: explicitly:
    #   create(:tool, scope: company)
    #   create(:tool, scope: project)

    # == Kind Traits ==

    trait :internal do
      kind { :internal }
      scope { nil }
      docker_image { nil }
    end

    # == State Traits ==

    trait :disabled do
      enabled { false }
    end

    # == Nested Associations ==

    trait :with_files do
      after(:create) do |tool|
        tool.tool_files.create!(path: "/workspace/main.py", content: "print('hello')")
        tool.tool_files.create!(path: "/workspace/config.yaml", content: "key: value")
      end
    end
  end
end
