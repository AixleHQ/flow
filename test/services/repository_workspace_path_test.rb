# frozen_string_literal: true

require "test_helper"

# Two repositories named `api` used to resolve to the same directory and silently
# overwrite each other, and a path recomputed later from a renamed remote stopped
# pointing at the checkout. Both are properties of the SET and of TIME, which is
# why the path is decided once and persisted.
class RepositoryWorkspacePathTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "a unique basename keeps the familiar bare path" do
    repository = create(:repository, full_name: "acme/api", scope: @project)

    assert_equal "/workspace/repo/api", RepositoryWorkspacePath.resolve([ repository ]).fetch(repository.id)
  end

  test "colliding basenames get distinct paths, including across hosts" do
    github = create(:repository, full_name: "acme/api", scope: @project)
    gitlab_integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)
    gitlab = create(:repository, full_name: "other/api", integration: gitlab_integration, scope: @project)

    paths = RepositoryWorkspacePath.resolve([ github, gitlab ])

    assert_equal 2, paths.values.uniq.size
    assert_includes paths[github.id], github.id.to_s
    assert_includes paths[gitlab.id], gitlab.id.to_s
  end

  test "Azure paths are always qualified so they do not depend on what else is attached" do
    integration = create(:integration, :azure_devops, :active, company: @company, connected_by: @user)
    repository = create(:repository, :azure_devops, integration: integration, scope: integration.project,
                                     azure_repository_name: "api")

    path = RepositoryWorkspacePath.resolve([ repository ]).fetch(repository.id)

    assert_equal "/workspace/repo/azure-#{repository.id}-api", path
  end

  test "a name that is not a safe directory atom collapses to one" do
    integration = create(:integration, :azure_devops, :active, company: @company, connected_by: @user)
    repository = create(:repository, :azure_devops, integration: integration, scope: integration.project,
                                     azure_repository_name: "My Service (v2)")

    path = RepositoryWorkspacePath.resolve([ repository ]).fetch(repository.id)

    assert_equal "/workspace/repo/azure-#{repository.id}-My-Service-v2", path
    refute_match(/[^A-Za-z0-9._\/-]/, path)
  end

  test "the persisted map wins over a recomputation after a rename" do
    repository = create(:repository, full_name: "acme/api", scope: @project)
    session = create(:terminal_session, :running, user: @user, project: @project)

    RepositoryWorkspacePath.persist!(session, RepositoryWorkspacePath.resolve([ repository ]))
    # The remote was renamed after the checkout existed. The files did not move.
    repository.update!(full_name: "acme/api-renamed")

    assert_equal "/workspace/repo/api", RepositoryWorkspacePath.for_session(session, [ repository ]).fetch(repository.id)
    assert_equal "/workspace/repo/api", RepositoryWorkspacePath.for_repository(session, repository)
  end

  test "a session with no stored map still resolves a path" do
    repository = create(:repository, full_name: "acme/api", scope: @project)
    session = create(:terminal_session, :running, user: @user, project: @project)

    assert_equal "/workspace/repo/api", RepositoryWorkspacePath.for_repository(session, repository)
  end
end
