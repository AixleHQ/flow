# frozen_string_literal: true

FactoryBot.define do
  factory :connector do
    sequence(:name) { |n| "io.github.example/connector-#{n}" }
    title { "Connector #{name.split('/').last}" }
    description { "Does something useful" }
    version { "1.0.0" }
    repository_url { "https://github.com/example/connector" }
    status { :active }
    is_latest { true }
    registry_updated_at { 1.day.ago }
    install_count { 0 }
    featured { false }
    bulk_publisher { false }
    normalizer_version { MCP::ConnectorManifest::VERSION.to_s }

    # Shaped like MCP::ConnectorManifest output, since that is what the mirror
    # actually stores and what installable_targets reads.
    manifest do
      {
        "name" => name,
        "title" => title,
        "version" => version,
        "targets" => [
          { "kind" => "remote", "transport" => "http", "url" => "https://mcp.example.com/mcp",
            "supported" => true, "unsupported_reason" => nil, "inputs" => [] }
        ]
      }
    end

    trait :package do
      manifest do
        {
          "name" => name,
          "targets" => [
            { "kind" => "package", "transport" => "stdio", "registry_type" => "npm",
              "identifier" => "@example/mcp", "version" => "1.0.0", "version_pinned" => true,
              "runtime" => "npx", "supported" => true, "unsupported_reason" => nil,
              "runtime_arguments" => [], "package_arguments" => [], "inputs" => [] }
          ]
        }
      end
    end

    trait :uninstallable do
      manifest do
        {
          "name" => name,
          "targets" => [
            { "kind" => "package", "transport" => "stdio", "registry_type" => "mcpb",
              "supported" => false, "unsupported_reason" => "no known runtime for mcpb packages", "inputs" => [] }
          ]
        }
      end
    end

    trait :deleted do
      status { :deleted }
    end

    trait :deprecated do
      status { :deprecated }
    end
  end
end
