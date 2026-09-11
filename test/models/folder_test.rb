# frozen_string_literal: true

require "test_helper"

class FolderTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  # ====== Validations ======

  test "valid folder with project scope" do
    folder = build(:folder, path: "docs", scope: @project, created_by: @owner)
    assert { folder.valid? }
  end

  test "valid folder with company scope" do
    folder = build(:folder, path: "docs", scope: @company, created_by: @owner)
    assert { folder.valid? }
  end

  test "path allows nested segments" do
    %w[dashboard dashboard/specs a/b/c my-docs templates_v2].each do |path|
      folder = build(:folder, path: path, scope: @project, created_by: @owner)
      assert { folder.valid? }
    end
  end

  test "path rejects leading, trailing or doubled slash" do
    [ "/dashboard", "dashboard/", "a//b" ].each do |path|
      folder = build(:folder, path: path, scope: @project, created_by: @owner)
      assert { !folder.valid? }
      assert { folder.errors[:path].present? }
    end
  end

  test "path rejects spaces" do
    folder = build(:folder, path: "my folder", scope: @project, created_by: @owner)
    assert { !folder.valid? }
    assert { folder.errors[:path].present? }
  end

  test "path must be present" do
    folder = build(:folder, path: nil, scope: @project, created_by: @owner)
    assert { !folder.valid? }
    assert { folder.errors[:path].present? }
  end

  test "path must be unique within scope" do
    create(:folder, path: "dashboard", scope: @project, created_by: @owner)
    folder = build(:folder, path: "dashboard", scope: @project, created_by: @owner)
    assert { !folder.valid? }
    assert { folder.errors[:path].present? }
  end

  test "same path allowed in different scopes" do
    create(:folder, path: "dashboard", scope: @company, created_by: @owner)
    folder = build(:folder, path: "dashboard", scope: @project, created_by: @owner)
    assert { folder.valid? }
  end

  test "scope_type validates inclusion in Company and Project" do
    validator = Folder.validators_on(:scope_type).find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }
    assert { validator.present? }
    assert { validator.options[:in] == %w[Company Project] }
  end

  test "created_by is required" do
    folder = build(:folder, scope: @project, created_by: nil)
    assert { !folder.valid? }
  end

  # ====== Derived path attributes ======

  test "label returns the last path segment" do
    assert { build(:folder, path: "dashboard").label == "dashboard" }
    assert { build(:folder, path: "dashboard/specs").label == "specs" }
  end

  test "parent_path returns nil for a root folder and the prefix for a nested one" do
    assert { build(:folder, path: "dashboard").parent_path.nil? }
    assert { build(:folder, path: "dashboard/specs").parent_path == "dashboard" }
    assert { build(:folder, path: "a/b/c").parent_path == "a/b" }
  end

  test "depth counts nesting level" do
    assert { build(:folder, path: "dashboard").depth == 0 }
    assert { build(:folder, path: "dashboard/specs").depth == 1 }
    assert { build(:folder, path: "a/b/c").depth == 2 }
  end

  test "ancestor_paths lists every ancestor, nearest first" do
    assert { build(:folder, path: "dashboard").ancestor_paths == [] }
    assert { build(:folder, path: "a/b/c").ancestor_paths == %w[a/b a] }
  end

  test "scope_indicator reflects scope_type" do
    assert { build(:folder, scope: @company).scope_indicator == "company" }
    assert { build(:folder, scope: @project).scope_indicator == "project" }
  end

  # ====== empty? ======

  test "empty? is true with no descendant folders or assets" do
    folder = create(:folder, path: "dashboard", scope: @project, created_by: @owner)
    assert { folder.empty? }
  end

  test "empty? is false when a child folder exists" do
    folder = create(:folder, path: "dashboard", scope: @project, created_by: @owner)
    create(:folder, path: "dashboard/specs", scope: @project, created_by: @owner)
    assert { !folder.empty? }
  end

  test "empty? is false when a descendant asset exists" do
    folder = create(:folder, path: "dashboard", scope: @project, created_by: @owner)
    create(:asset, folder: "dashboard/specs", scope: @project, created_by: @owner)
    assert { !folder.empty? }
  end

  test "empty? ignores soft-deleted assets" do
    folder = create(:folder, path: "dashboard", scope: @project, created_by: @owner)
    create(:asset, folder: "dashboard", scope: @project, created_by: @owner, deleted_at: Time.current)
    assert { folder.empty? }
  end

  # ====== Scopes ======

  test ".for_project returns only project-scoped folders" do
    create(:folder, path: "p", scope: @project, created_by: @owner)
    create(:folder, path: "c", scope: @company, created_by: @owner)

    result = Folder.for_project(@project)
    assert { result.count == 1 }
    assert { result.first.path == "p" }
  end

  test ".for_company returns only company-scoped folders" do
    create(:folder, path: "p", scope: @project, created_by: @owner)
    create(:folder, path: "c", scope: @company, created_by: @owner)

    result = Folder.for_company(@company)
    assert { result.count == 1 }
    assert { result.first.path == "c" }
  end

  test ".accessible_from_project returns the project's own folders and its company's folders" do
    create(:folder, path: "p", scope: @project, created_by: @owner)
    create(:folder, path: "c", scope: @company, created_by: @owner)
    other_company = create(:company)
    create(:folder, path: "unrelated", scope: other_company, created_by: @owner)

    result = Folder.accessible_from_project(@project)
    assert { result.pluck(:path).sort == %w[c p] }
  end

  test "dependent destroy: destroying the project removes its folders" do
    create(:folder, path: "p", scope: @project, created_by: @owner)
    assert { Folder.for_project(@project).count == 1 }

    @project.destroy!
    assert { Folder.where(scope_type: "Project", scope_id: @project.id).count.zero? }
  end
end
