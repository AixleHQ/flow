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

  test "integration must be a code host" do
    linear = create(:integration, :linear, company: @company, connected_by: @user)
    repo = build(:repository, scope: @project, integration: linear)

    assert { !repo.valid? }
    assert { repo.errors[:integration].present? }
  end

  test "github repository owner must match the installation account when it is known" do
    @integration.update!(settings: { "account_login" => "acme" })

    mismatched = build(:repository, full_name: "other-org/app", scope: @project, integration: @integration)
    assert { !mismatched.valid? }
    assert_match(/acme/, mismatched.errors[:full_name].to_sentence)

    matching = build(:repository, full_name: "ACME/app", scope: @project, integration: @integration)
    assert { matching.valid? }
  end

  test "owner is not checked against installations that never recorded an account" do
    repo = build(:repository, full_name: "any-org/app", scope: @project, integration: @integration)
    assert { repo.valid? }
  end

  # ====== Public sources ======

  test "public repository is valid without an integration" do
    repo = build(:repository, :public_source, full_name: "rails/rails",
                 clone_url: "https://github.com/rails/rails.git", scope: @project)

    assert repo.valid?, repo.errors.full_messages.to_sentence
    assert repo.public_source?
    assert_equal "github", repo.provider
  end

  test "public repository is forced to non-private" do
    repo = create(:repository, :public_source, full_name: "rails/rails", is_private: true,
                  clone_url: "https://github.com/rails/rails.git", scope: @project)

    assert_equal false, repo.is_private # rubocop:disable Minitest/RefuteFalse
  end

  test "public clone_url must be the anonymous https url of full_name on an allowlisted host" do
    [
      "https://evil.com/rails/rails.git",
      "http://github.com/rails/rails.git",
      "https://user:token@github.com/rails/rails.git",
      "https://github.com/other/repo.git",
      "https://github.com/rails/rails.git?x=1",
      "https://github.com:8443/rails/rails.git"
    ].each do |clone_url|
      repo = build(:repository, :public_source, full_name: "rails/rails", clone_url: clone_url, scope: @project)

      assert { !repo.valid? }
      assert repo.errors[:clone_url].present?, "expected #{clone_url} to be rejected"
    end
  end

  test "public gitlab repository derives its provider from the clone host" do
    repo = build(:repository, :public_source, full_name: "group/sub/app",
                 clone_url: "https://gitlab.com/group/sub/app.git", scope: @project)

    assert repo.valid?, repo.errors.full_messages.to_sentence
    assert_equal "gitlab", repo.provider
  end

  test "public_sources scope returns only integration-less repositories" do
    create(:repository, full_name: "org/app", scope: @project, integration: @integration)
    public_repo = create(:repository, :public_source, full_name: "rails/rails",
                         clone_url: "https://github.com/rails/rails.git", scope: @project)

    assert_equal [ public_repo.id ], Repository.public_sources.pluck(:id)
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
