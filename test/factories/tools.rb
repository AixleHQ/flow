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

    trait :project do
    end

    # == Kind Traits ==

    trait :system do
      kind { :system }
      source { "code" }
      scope { nil }
    end

    trait :internal do
      kind { :internal }
      source { "code" }
      execution_mode { :app }
      scope { nil }
      docker_image { nil }
    end

    trait :workflow do
      kind { :workflow }
      source { "code" }
      execution_mode { :app }
      scope { nil }
      docker_image { nil }
    end

    trait :meta do
      kind { :meta }
      source { "code" }
      user_attachable { false }
      execution_mode { :app }
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
