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

  test "valid repository with company scope" do
    repo = build(:repository, scope: @company, integration: @integration)
    assert { repo.valid? }
  end

  test "valid repository with project scope" do
    repo = build(:repository, scope: @project, integration: @integration)
    assert { repo.valid? }
  end

  test "full_name must be present" do
    repo = build(:repository, full_name: nil, scope: @company, integration: @integration)
    assert { !repo.valid? }
    assert { repo.errors[:full_name].present? }
  end

  test "full_name must be in owner/repo format" do
    repo = build(:repository, full_name: "invalid", scope: @company, integration: @integration)
    assert { !repo.valid? }

    repo.full_name = "owner/repo"
    assert { repo.valid? }
  end

  test "full_name allows dots hyphens and underscores" do
    repo = build(:repository, full_name: "my.org/my_repo-name.v2", scope: @company, integration: @integration)
    assert { repo.valid? }
  end

  test "full_name unique within scope" do
    create(:repository, full_name: "org/app", scope: @company, integration: @integration)
    dup = build(:repository, full_name: "org/app", scope: @company, integration: @integration)
    assert { !dup.valid? }
    assert { dup.errors[:full_name].present? }
  end

  test "same full_name in different scopes is allowed" do
    create(:repository, full_name: "org/app", scope: @company, integration: @integration)
    project_repo = build(:repository, full_name: "org/app", scope: @project, integration: @integration)
    assert { project_repo.valid? }
  end

  test "source_branch must be present" do
    repo = build(:repository, source_branch: nil, scope: @company, integration: @integration)
    assert { !repo.valid? }
  end

  test "clone_url must be present" do
    repo = build(:repository, clone_url: nil, scope: @company, integration: @integration)
    assert { !repo.valid? }
  end

  test "scope_type must be Company or Project" do
    repo = build(:repository, scope: @company, integration: @integration)
    assert { repo.valid? }

    repo.scope_type = "User"
    assert { !repo.valid? }
  end

  # ====== Scopes ======

  test "for_company scope" do
    create(:repository, full_name: "org/a", scope: @company, integration: @integration)
    create(:repository, full_name: "org/b", scope: @project, integration: @integration)

    results = Repository.for_company(@company)
    assert_equal 1, results.count
    assert_equal "org/a", results.first.full_name
  end

  test "for_project scope" do
    create(:repository, full_name: "org/a", scope: @company, integration: @integration)
    create(:repository, full_name: "org/b", scope: @project, integration: @integration)

    results = Repository.for_project(@project)
    assert_equal 1, results.count
    assert_equal "org/b", results.first.full_name
  end

  test "for_integration scope" do
    other_integration = create(:integration, :github, company: @company, connected_by: @user, name: "other")
    create(:repository, full_name: "org/a", scope: @company, integration: @integration)
    create(:repository, full_name: "org/b", scope: @company, integration: other_integration)

    results = Repository.for_integration(@integration)
    assert_equal 1, results.count
    assert_equal "org/a", results.first.full_name
  end

  # ====== merged_for_project ======

  test "merged_for_project returns company + project repos" do
    create(:repository, full_name: "org/shared", scope: @company, integration: @integration)
    create(:repository, full_name: "org/app", scope: @project, integration: @integration)

    merged = Repository.merged_for_project(@project)
    assert_equal 2, merged.length
    names = merged.map(&:full_name)
    assert { names.include?("org/shared") }
    assert { names.include?("org/app") }
  end

  test "merged_for_project adds scope_indicator" do
    create(:repository, full_name: "org/shared", scope: @company, integration: @integration)
    create(:repository, full_name: "org/app", scope: @project, integration: @integration)

    merged = Repository.merged_for_project(@project)
    indicators = merged.map { |r| [ r.full_name, r.scope_indicator ] }.to_h
    assert_equal "company", indicators["org/shared"]
    assert_equal "project", indicators["org/app"]
  end

  test "merged_for_project deduplicates by full_name favoring project" do
    create(:repository, full_name: "org/app", scope: @company, integration: @integration)
    create(:repository, full_name: "org/app", scope: @project, integration: @integration)

    merged = Repository.merged_for_project(@project)
    assert_equal 1, merged.length
    assert_equal "project", merged.first.scope_indicator
  end

  # ====== Methods ======

  test "repo_name returns last segment" do
    repo = build(:repository, full_name: "acme/my-app")
    assert_equal "my-app", repo.repo_name
  end

  # ====== Associations ======

  test "belongs to integration" do
    repo = create(:repository, scope: @company, integration: @integration)
    assert_equal @integration, repo.integration
  end

  test "destroying integration destroys repositories" do
    create(:repository, scope: @company, integration: @integration)
    assert_difference("Repository.count", -1) do
      @integration.destroy
    end
  end
end
