# frozen_string_literal: true

FactoryBot.define do
  factory :mcp_server do
    sequence(:name) { |n| "mcp-server-#{n}" }
    kind { :custom }
    transport { :sse }
    url { "https://mcp.example.com/v1" }
    description { "Test MCP server" }
    enabled { true }

    # Custom servers are Project-scoped only.
    scope factory: %i[project standalone]

    # == Kind Traits ==

    trait :internal do
      kind { :internal }
      scope { nil }
      url { nil }
    end

    trait :custom do
      kind { :custom }
      scope factory: %i[project standalone]
    end

    # == Common Configurations ==

    trait :with_headers do
      headers { { "Authorization" => "Bearer test-token" } }
    end

    trait :disabled do
      enabled { false }
    end

    trait :stdio_transport do
      transport { :stdio }
      url { nil }
    end
  end
end
