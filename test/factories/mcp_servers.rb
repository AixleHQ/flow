# frozen_string_literal: true

FactoryBot.define do
  factory :mcp_server do
    sequence(:name) { |n| "mcp-server-#{n}" }
    sequence(:display_name) { |n| "MCP Server #{n}" }
    kind { :custom }
    transport { :sse }
    url { "http://localhost:3001/mcp" }
    description { "Test MCP server" }
    enabled { true }

    # Custom servers need a scope
    scope { nil }

    # == Kind Traits ==

    trait :internal do
      kind { :internal }
      scope { nil }
      url { nil }
    end

    trait :custom do
      kind { :custom }
      # Scope must be set explicitly for custom servers
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
