# frozen_string_literal: true

FactoryBot.define do
  factory :repository do
    sequence(:full_name) { |n| "org/repo-#{n}" }
    source_branch { "main" }
    clone_url { "https://github.com/#{full_name}.git" }
    is_private { false }
    description { "Repository #{full_name}" }
    integration
    # Repositories are Project-scoped only.
    scope factory: %i[project standalone]

    trait :project_scope do
      scope factory: %i[project standalone]
    end

    trait :private do
      is_private { true }
    end

    # Attached without an integration: cloned anonymously, read-only.
    trait :public_source do
      integration { nil }
    end

    # Azure identity is the organization + project + repository GUID triple;
    # `full_name` is a display value carrying the provider discriminator, and the
    # project GUID has to match the integration's selected project.
    trait :azure_devops do
      transient do
        # Sequenced: `full_name` is unique per scope, so two bare
        # `create(:repository, :azure_devops)` calls in one project must not
        # collide on the display name.
        sequence(:azure_repository_name) { |n| "api-#{n}" }
      end

      integration factory: %i[integration azure_devops active]
      external_id { SecureRandom.uuid }
      external_organization_id { SecureRandom.uuid }
      clone_url { nil }
      full_name { nil }

      after(:build) do |repository, evaluator|
        integration = repository.integration
        repository.external_project_id ||= integration&.azure_project_id
        organization = integration&.azure_organization_slug || "contoso"
        project = integration&.azure_project_name || "Customer Platform"
        repository.full_name ||=
          "#{Repository::AZURE_FULL_NAME_PREFIX}#{organization}/#{project}/#{evaluator.azure_repository_name}"
      end
    end
  end
end
