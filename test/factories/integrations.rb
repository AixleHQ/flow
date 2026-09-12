# frozen_string_literal: true

FactoryBot.define do
  factory :integration do
    sequence(:name) { |n| "org-#{n}" }
    provider { :github }
    status { :inactive }
    company
    connected_by factory: %i[user]

    after(:build) do |integration|
      integration.credentials_data = { installation_id: rand(10_000..99_999).to_s }
    end

    trait :github do
      provider { :github }
    end

    trait :gitlab do
      provider { :gitlab }
      after(:build) do |integration|
        integration.credentials_data = { personal_access_token: "glpat-test_#{SecureRandom.hex(8)}" }
      end
    end

    trait :linear do
      provider { :linear }
      after(:build) do |integration|
        integration.credentials_data = { access_token: "lin_api_test_#{SecureRandom.hex(8)}" }
      end
    end

    trait :coder do
      provider { :coder }
      after(:build) do |integration|
        integration.credentials_data = {
          coder_url: "https://coder.example.com",
          session_token: "coder-test-#{SecureRandom.hex(8)}",
          user_id: SecureRandom.uuid
        }
        integration.settings = {
          coder_username:   "test-user",
          coder_user_email: "test@example.com",
          lock_ttl_minutes: 60
        }
      end
    end

    # Azure connections are project-scoped by validation and name one Azure
    # project. The installation carries the approval; `azure_project_id` must be
    # inside its approved scope or the record will not save.
    trait :azure_devops do
      provider { :azure_devops }

      transient do
        azure_project_id { SecureRandom.uuid }
        enabled_capabilities { AzureDevops::IntegrationService::DEFAULT_CAPABILITIES }
      end

      # Both the project and the installation have to sit in the integration's
      # own company — the model rejects the record otherwise, which is the point
      # of those validations.
      project { association(:project, company: company, owner: association(:user, company: company)) }
      azure_devops_installation do
        association(:azure_devops_installation, :active, :approved,
                    company: company, allowed_project_ids: [ azure_project_id ])
      end

      after(:build) do |integration, evaluator|
        installation = integration.azure_devops_installation
        integration.credentials_data = {}
        integration.settings = {
          "auth_mode" => "service_principal",
          "organization_slug" => installation&.organization_slug,
          "tenant_id" => installation&.tenant_id,
          "client_id" => installation&.client_id,
          "azure_project_id" => evaluator.azure_project_id,
          "azure_project_name" => "Customer Platform",
          "enabled_capabilities" => evaluator.enabled_capabilities
        }.compact
      end
    end

    # The fallback identity mode: acts as the token's owner, carries no
    # installation, and is gated on Settings.azure_devops.pat_mode_enabled.
    trait :azure_devops_pat do
      provider { :azure_devops }
      azure_devops_installation { nil }

      transient do
        azure_project_id { SecureRandom.uuid }
      end

      project { association(:project, company: company, owner: association(:user, company: company)) }

      after(:build) do |integration, evaluator|
        integration.credentials_data = { "personal_access_token" => "azdo-test-#{SecureRandom.hex(8)}" }
        integration.settings = {
          "auth_mode" => "pat",
          "organization_slug" => "contoso",
          "azure_project_id" => evaluator.azure_project_id,
          "enabled_capabilities" => AzureDevops::IntegrationService::DEFAULT_CAPABILITIES
        }
      end
    end

    trait :active do
      status { :active }
    end

    trait :error do
      status { :error }
      settings { { error: "Connection failed" } }
    end
  end
end
