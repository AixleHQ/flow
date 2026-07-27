# frozen_string_literal: true

require "test_helper"

class RepositoryTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @integration = create(:integration, :github, :active, company: @company, connected_by: @user)
  end

  # ====== Validations ======

  test "valid repository with project scope" do
    repo = build(:repository, scope: @project, integration: @integration)
    assert { repo.valid? }
  end

  test "full_name must be present" do
    repo = build(:repository, full_name: nil, scope: @project, integration: @integration)
    assert { !repo.valid? }
    assert { repo.errors[:full_name].present? }
  end

  test "full_name must be in owner/repo format" do
    repo = build(:repository, full_name: "invalid", scope: @project, integration: @integration)
    assert { !repo.valid? }

    repo.full_name = "owner/repo"
    assert { repo.valid? }
  end

  test "full_name allows dots hyphens and underscores" do
    repo = build(:repository, full_name: "my.org/my_repo-name.v2", scope: @project, integration: @integration)
    assert { repo.valid? }
  end

  test "full_name unique within scope" do
    create(:repository, full_name: "org/app", scope: @project, integration: @integration)
    dup = build(:repository, full_name: "org/app", scope: @project, integration: @integration)
    assert { !dup.valid? }
    assert { dup.errors[:full_name].present? }
  end

  test "same full_name in different scopes is allowed" do
    other_project = create(:project, company: @company, owner: @user)
    create(:repository, full_name: "org/app", scope: other_project, integration: @integration)
    project_repo = build(:repository, full_name: "org/app", scope: @project, integration: @integration)
    assert { project_repo.valid? }
  end

  test "source_branch must be present" do
    repo = build(:repository, source_branch: nil, scope: @project, integration: @integration)
    assert { !repo.valid? }
  end

  test "clone_url must be present" do
    repo = build(:repository, clone_url: nil, full_name: nil, scope: @project, integration: @integration)
    assert { !repo.valid? }
    assert { repo.errors[:clone_url].present? }
  end

  test "scope_type must be Project" do
    repo = build(:repository, scope: @project, integration: @integration)
    assert { repo.valid? }

    repo.scope = @company
    assert { !repo.valid? }

    repo.scope_type = "User"
    assert { !repo.valid? }
  end

  # ====== Scopes ======

  test "for_project scope" do
    other_project = create(:project, company: @company, owner: @user)
    create(:repository, full_name: "org/a", scope: other_project, integration: @integration)
    create(:repository, full_name: "org/b", scope: @project, integration: @integration)

    results = Repository.for_project(@project)
    assert_equal 1, results.count
    assert_equal "org/b", results.first.full_name
  end

  test "for_integration scope" do
    other_integration = create(:integration, :github, company: @company, connected_by: @user, name: "other")
    create(:repository, full_name: "org/a", scope: @project, integration: @integration)
    create(:repository, full_name: "org/b", scope: @project, integration: other_integration)

    results = Repository.for_integration(@integration)
    assert_equal 1, results.count
    assert_equal "org/a", results.first.full_name
  end

  # ====== visible_for_project ======

  test "visible_for_project returns the project repos" do
    create(:repository, full_name: "org/shared", scope: @project, integration: @integration)
    create(:repository, full_name: "org/app", scope: @project, integration: @integration)

    result = Repository.visible_for_project(@project)
    names = result.pluck(:full_name)

    assert_includes names, "org/shared"
    assert_includes names, "org/app"
  end

  test "visible_for_project scope_indicator via instance method" do
    create(:repository, full_name: "org/app", scope: @project, integration: @integration)

    result = Repository.visible_for_project(@project)
    project_repo = result.find_by(full_name: "org/app")

    assert_equal "project", project_repo.scope_indicator
  end

  test "visible_for_project returns ActiveRecord::Relation" do
    result = Repository.visible_for_project(@project)
    assert_kind_of ActiveRecord::Relation, result
  end

  # ====== Methods ======

  test "repo_name returns last segment" do
    repo = build(:repository, full_name: "acme/my-app")
    assert_equal "my-app", repo.repo_name
  end

  # ====== Associations ======

  test "belongs to integration" do
    repo = create(:repository, scope: @project, integration: @integration)
    assert_equal @integration, repo.integration
  end

  test "destroying integration destroys repositories" do
    create(:repository, scope: @project, integration: @integration)
    assert_difference("Repository.count", -1) do
      @integration.destroy
    end
  end
end
