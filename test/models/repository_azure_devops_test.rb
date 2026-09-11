# frozen_string_literal: true

require "test_helper"

# The Repository rules that an Azure row runs into. Each of these was a hard save
# failure before the provider was added, and each is easy to regress by tightening
# one validation for the other providers.
class RepositoryAzureDevopsTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
  end

  test "an Azure integration is accepted as a code host" do
    repository = build(:repository, :azure_devops, integration: @integration, scope: @integration.project)

    assert repository.valid?, repository.errors.full_messages.to_sentence
  end

  test "a display name with a space and the provider discriminator is valid" do
    repository = build(:repository, :azure_devops, integration: @integration, scope: @integration.project)
    repository.full_name = "azure_devops:contoso/Customer Platform/api"

    assert repository.valid?, repository.errors.full_messages.to_sentence
  end

  test "the owner/repo format still holds for every other provider" do
    github = create(:integration, :github, :active)
    repository = build(:repository, integration: github, scope: create(:project, :standalone),
                                    full_name: "azure_devops:contoso/Customer Platform/api")

    refute_predicate repository, :valid?
    assert_includes repository.errors[:full_name].to_sentence, "owner/repo format"
  end

  test "an Azure row without its identity triple is rejected" do
    repository = build(:repository, :azure_devops, integration: @integration, scope: @integration.project)
    repository.assign_attributes(external_id: nil, external_project_id: nil, external_organization_id: nil)

    refute_predicate repository, :valid?
    assert_includes repository.errors[:external_id], "is required for an Azure DevOps repository"
    assert_includes repository.errors[:external_project_id], "is required for an Azure DevOps repository"
    assert_includes repository.errors[:external_organization_id], "is required for an Azure DevOps repository"
  end

  test "a repository from another Azure project cannot be attached to this connection" do
    repository = build(:repository, :azure_devops, integration: @integration, scope: @integration.project,
                                    external_project_id: SecureRandom.uuid)

    refute_predicate repository, :valid?
    assert_includes repository.errors[:external_project_id].to_sentence, "selected Azure project"
  end

  test "the clone url is derived credential-free with each path component encoded" do
    repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project,
                                     azure_repository_name: "api")

    assert_equal "https://dev.azure.com/#{@integration.azure_organization_slug}/Customer%20Platform/_git/api",
                 repository.clone_url
    refute_includes repository.clone_url, "@"
  end

  test "azure_display_parts splits the display name without touching the API identity" do
    repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project,
                                     azure_repository_name: "api")

    parts = repository.azure_display_parts
    assert_equal @integration.azure_organization_slug, parts[:organization]
    assert_equal "Customer Platform", parts[:project]
    assert_equal "api", parts[:repository]
    # The names are display values; the GUIDs are what the API routes on.
    refute_equal parts[:project], repository.external_project_id
  end

  test "two Azure repositories with the same name in one project cannot both attach" do
    project = @integration.project
    external_id = SecureRandom.uuid
    create(:repository, :azure_devops, integration: @integration, scope: project, external_id: external_id)

    # Renamed upstream, same repository: the display name moved and the identity
    # triple did not, which is exactly what the partial index is for.
    duplicate = build(:repository, :azure_devops, integration: @integration, scope: project,
                                   external_id: external_id, azure_repository_name: "api-renamed")
    duplicate.external_organization_id = Repository.last.external_organization_id
    duplicate.clone_url = "https://dev.azure.com/contoso/Customer%20Platform/_git/api-renamed"

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "provider reads through the integration" do
    repository = create(:repository, :azure_devops, integration: @integration, scope: @integration.project)

    assert_equal "azure_devops", repository.provider
    assert repository.azure_devops?
  end
end
