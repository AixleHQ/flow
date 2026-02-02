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
    association :scope, factory: :company

    trait :internal do
      kind { :internal }
      scope { nil }
      docker_image { nil }
    end

    trait :project do
      association :scope, factory: :project
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_files do
      after(:create) do |tool|
        tool.tool_files.create!(path: "/workspace/main.py", content: "print('hello')")
        tool.tool_files.create!(path: "/workspace/config.yaml", content: "key: value")
      end
    end
  end
end
