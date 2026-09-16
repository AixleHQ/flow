# frozen_string_literal: true

require "test_helper"

class AssetTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  # ====== Validations ======

  test "valid asset with company scope" do
    asset = build(:asset, scope: @company, created_by: @owner)
    assert { asset.valid? }
  end

  test "valid asset with project scope" do
    asset = build(:asset, scope: @project, created_by: @owner)
    assert { asset.valid? }
  end

  test "name must be present" do
    asset = build(:asset, name: nil, scope: @company, created_by: @owner)
    assert { !asset.valid? }
    assert { asset.errors[:name].present? }
  end

  test "name must be unique within scope" do
    create(:asset, name: "duplicate.md", scope: @company, created_by: @owner)
    asset = build(:asset, name: "duplicate.md", scope: @company, created_by: @owner)
    assert { !asset.valid? }
    assert { asset.errors[:name].present? }
  end

  test "same name allowed in different scopes" do
    create(:asset, name: "shared.md", scope: @company, created_by: @owner)
    asset = build(:asset, name: "shared.md", scope: @project, created_by: @owner)
    assert { asset.valid? }
  end

  test "scope_type validates inclusion in Company and Project" do
    validator = Asset.validators_on(:scope_type).find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }
    assert { validator.present? }
    assert { validator.options[:in] == %w[Company Project] }
  end

  test "scope_id must be present" do
    asset = Asset.new(name: "test.md", scope_type: "Company", scope_id: nil, created_by: @owner)
    assert { !asset.valid? }
    assert { asset.errors[:scope_id].present? }
  end

  test "created_by is required" do
    asset = build(:asset, scope: @company, created_by: nil)
    assert { !asset.valid? }
  end

  # ====== Folder ======

  test "folder allows valid names" do
    [ "architecture", "reports", "my-docs", "templates_v2", "Q3 reports", "Отчёты", "notes (draft)" ].each do |name|
      asset = build(:asset, folder: name, scope: @company, created_by: @owner)
      assert asset.valid?, asset.errors.full_messages.to_sentence
    end
  end

  # A folder is one flat label, not a path: a separator would let it address a directory of its
  # own choosing under /workspace/assets.
  test "folder rejects path separators, traversal and control characters" do
    [ "level1/level2", "level1\\level2", ".", "..", "tabbed\tname", "a" * 101 ].each do |name|
      asset = build(:asset, folder: name, scope: @company, created_by: @owner)
      assert { !asset.valid? }
      assert { asset.errors[:folder].present? }
    end
  end

  # Asset names have always been free-form, and the folder is half of the same path — every
  # consumer shell-escapes it, so there is nothing for a space to break.
  test "folder allows spaces" do
    asset = build(:asset, folder: "my folder", scope: @company, created_by: @owner)
    assert asset.valid?, asset.errors.full_messages.to_sentence
  end

  test "folder allows blank" do
    asset = build(:asset, folder: nil, scope: @company, created_by: @owner)
    assert { asset.valid? }
  end

  test "folder is trimmed on write and a blank folder is stored as root" do
    asset = create(:asset, folder: "  docs  ", scope: @company, created_by: @owner)
    assert_equal "docs", asset.folder

    rooted = create(:asset, folder: "   ", scope: @company, created_by: @owner)
    assert_nil rooted.folder
  end

  test ".normalize_folder canonicalizes a lookup key the same way a write is canonicalized" do
    assert_equal "docs", Asset.normalize_folder(" docs ")
    assert_equal "my folder", Asset.normalize_folder("  my folder  ")
    assert_nil Asset.normalize_folder("")
    assert_nil Asset.normalize_folder(nil)
  end

  test ".invalid_folder? mirrors the validation for callers that reject before building a record" do
    assert { !Asset.invalid_folder?("my folder") }
    assert { !Asset.invalid_folder?(nil) }
    assert { !Asset.invalid_folder?("  ") }
    assert { Asset.invalid_folder?("docs/sub") }
    assert { Asset.invalid_folder?("..") }
    assert { Asset.invalid_folder?("a" * 101) }
  end

  test "same name in different folders is allowed" do
    create(:asset, name: "readme.md", folder: "architecture", scope: @project, created_by: @owner)
    asset = build(:asset, name: "readme.md", folder: "reports", scope: @project, created_by: @owner)
    assert { asset.valid? }
  end

  test "same name in same folder is rejected" do
    create(:asset, name: "readme.md", folder: "docs", scope: @project, created_by: @owner)
    asset = build(:asset, name: "readme.md", folder: "docs", scope: @project, created_by: @owner)
    assert { !asset.valid? }
  end

  # ====== Scopes ======

  test ".for_company returns company-scoped assets" do
    create(:asset, name: "company-asset.md", scope: @company, created_by: @owner)
    create(:asset, name: "project-asset.md", scope: @project, created_by: @owner)

    result = Asset.for_company(@company)
    assert { result.count == 1 }
    assert { result.first.name == "company-asset.md" }
  end

  test ".for_project returns project-scoped assets" do
    create(:asset, name: "company-asset.md", scope: @company, created_by: @owner)
    create(:asset, name: "project-asset.md", scope: @project, created_by: @owner)

    result = Asset.for_project(@project)
    assert { result.count == 1 }
    assert { result.first.name == "project-asset.md" }
  end

  # ====== visible_for_project ======

  test ".visible_for_project includes company and project assets" do
    create(:asset, name: "a-company.md", scope: @company, created_by: @owner)
    create(:asset, name: "b-project.md", scope: @project, created_by: @owner)

    result = Asset.visible_for_project(@project)
    names = result.pluck(:name)

    assert { names.include?("a-company.md") }
    assert { names.include?("b-project.md") }
  end

  test ".visible_for_project scope_indicator via instance method" do
    create(:asset, name: "a-company.md", scope: @company, created_by: @owner)
    create(:asset, name: "b-project.md", scope: @project, created_by: @owner)

    result = Asset.visible_for_project(@project)

    company_asset = result.find_by(name: "a-company.md")
    project_asset = result.find_by(name: "b-project.md")

    assert_equal "company", company_asset.scope_indicator
    assert_equal "project", project_asset.scope_indicator
  end

  test ".visible_for_project includes both company and project with same name" do
    create(:asset, name: "shared.md", scope: @company, created_by: @owner)
    create(:asset, name: "shared.md", scope: @project, created_by: @owner)

    result = Asset.visible_for_project(@project)
    shared = result.where(name: "shared.md")

    assert_equal 2, shared.count
  end

  test ".visible_for_project excludes other company assets" do
    other_company = create(:company, email_domain: "other-assets.com")
    other_owner = create(:user, :employee, company: other_company)
    create(:asset, name: "other.md", scope: other_company, created_by: other_owner)

    result = Asset.visible_for_project(@project)
    names = result.pluck(:name)

    assert { !names.include?("other.md") }
  end

  test ".visible_for_project returns ActiveRecord::Relation" do
    result = Asset.visible_for_project(@project)
    assert { result.is_a?(ActiveRecord::Relation) }
  end

  # ====== Soft Delete ======

  test "#soft_delete! sets deleted_at" do
    asset = create(:asset, scope: @project, created_by: @owner)
    assert { asset.deleted_at.nil? }

    asset.soft_delete!
    assert { asset.deleted_at.present? }
    assert { asset.deleted? }
  end

  test "#restore! clears deleted_at" do
    asset = create(:asset, scope: @project, created_by: @owner)
    asset.soft_delete!
    assert { asset.deleted? }

    asset.restore!
    assert { asset.deleted_at.nil? }
    assert { !asset.deleted? }
  end

  test ".active excludes deleted assets" do
    active = create(:asset, name: "active.md", scope: @project, created_by: @owner)
    deleted = create(:asset, name: "deleted.md", scope: @project, created_by: @owner)
    deleted.soft_delete!

    result = Asset.active
    assert { result.include?(active) }
    assert { !result.include?(deleted) }
  end

  test ".deleted returns only deleted assets" do
    create(:asset, name: "active.md", scope: @project, created_by: @owner)
    deleted = create(:asset, name: "deleted.md", scope: @project, created_by: @owner)
    deleted.soft_delete!

    result = Asset.deleted
    assert { result.include?(deleted) }
    assert { result.count == 1 }
  end

  test ".for_company excludes deleted assets" do
    create(:asset, name: "active.md", scope: @company, created_by: @owner)
    deleted = create(:asset, name: "deleted.md", scope: @company, created_by: @owner)
    deleted.soft_delete!

    result = Asset.for_company(@company)
    assert { result.count == 1 }
    assert { result.first.name == "active.md" }
  end

  test ".for_project excludes deleted assets" do
    create(:asset, name: "active.md", scope: @project, created_by: @owner)
    deleted = create(:asset, name: "deleted.md", scope: @project, created_by: @owner)
    deleted.soft_delete!

    result = Asset.for_project(@project)
    assert { result.count == 1 }
    assert { result.first.name == "active.md" }
  end

  test ".visible_for_project excludes deleted assets" do
    create(:asset, name: "active.md", scope: @project, created_by: @owner)
    deleted = create(:asset, name: "deleted.md", scope: @company, created_by: @owner)
    deleted.soft_delete!

    result = Asset.visible_for_project(@project)
    names = result.pluck(:name)
    assert { names.include?("active.md") }
    assert { !names.include?("deleted.md") }
  end

  test ".accessible_from_project excludes deleted assets" do
    active = create(:asset, name: "active.md", scope: @project, created_by: @owner)
    deleted = create(:asset, name: "deleted.md", scope: @company, created_by: @owner)
    deleted.soft_delete!

    result = Asset.accessible_from_project(@project)
    assert { result.include?(active) }
    assert { !result.include?(deleted) }
  end

  # ====== latest_version ======

  test "#latest_version returns highest version" do
    asset = create(:asset, scope: @project, created_by: @owner)
    create(:asset_version, asset: asset, version: 1, uploaded_by: @owner)
    v2 = create(:asset_version, asset: asset, version: 2, uploaded_by: @owner)

    assert { asset.latest_version.id == v2.id }
  end

  test "#latest_version returns nil when no versions" do
    asset = create(:asset, scope: @project, created_by: @owner)
    assert { asset.latest_version.nil? }
  end

  # ====== Sharing ======

  test "#share_url returns nil until shared" do
    asset = create(:asset, scope: @project, created_by: @owner)
    assert { asset.share_url.nil? }
  end

  test "#share_url returns a stable public link once shared" do
    asset = create(:asset, scope: @project, created_by: @owner)
    asset.share!

    assert { asset.shared? }
    assert_includes asset.share_url, "/share/#{asset.public_token}"
  end

  # ====== Associations ======

  test "company has_many assets" do
    asset = create(:asset, name: "assoc-test.md", scope: @company, created_by: @owner)
    assert { @company.assets.include?(asset) }
  end

  test "project has_many assets" do
    asset = create(:asset, name: "assoc-test.md", scope: @project, created_by: @owner)
    assert { @project.assets.include?(asset) }
  end

  test "destroying company destroys its assets" do
    company = create(:company, email_domain: "doomed-co.com")
    create(:asset, name: "doomed.md", scope: company, created_by: @owner)

    assert_difference("Asset.count", -1) do
      company.destroy
    end
  end

  test "destroying project destroys its assets" do
    project = create(:project, company: @company, owner: @owner)
    create(:asset, name: "doomed.md", scope: project, created_by: @owner)

    assert_difference("Asset.count", -1) do
      project.destroy
    end
  end

  test "destroying asset destroys its versions" do
    asset = create(:asset, scope: @project, created_by: @owner)
    create(:asset_version, asset: asset, version: 1, uploaded_by: @owner)
    create(:asset_version, asset: asset, version: 2, uploaded_by: @owner)

    assert_difference("AssetVersion.count", -2) do
      asset.destroy
    end
  end
end
