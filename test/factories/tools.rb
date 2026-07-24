# frozen_string_literal: true

FactoryBot.define do
  factory :tool do
    sequence(:name) { |n| "tool_#{n}" }
    display_name { name.titleize }
    docker_image { "alpine:latest" }
    enabled { true }
    required_config_items { [] }
    input_schema { {} }
    # Custom (db-source) tools are Project-scoped only; code traits below reset to nil.
    scope factory: %i[project standalone]

    # == Association Traits ==

    trait :with_project_scope do
      scope factory: %i[project standalone]
    end

    trait :project do
    end

    # == Kind Traits ==

    trait :system do
      source { "code" }
      tags { %w[coder] }
      scope { nil }
    end

    trait :internal do
      source { "code" }
      tags { %w[async_results] }
      execution_mode { :app }
      scope { nil }
      docker_image { nil }
    end

    trait :workflow do
      source { "code" }
      tags { %w[board] }
      execution_mode { :app }
      scope { nil }
      docker_image { nil }
    end

    trait :meta do
      source { "code" }
      tags { %w[builder] }
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
