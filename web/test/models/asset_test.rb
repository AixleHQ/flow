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
    %w[architecture reports my-docs templates_v2].each do |name|
      asset = build(:asset, folder: name, scope: @company, created_by: @owner)
      assert { asset.valid? }
    end
  end

  test "folder rejects slashes" do
    asset = build(:asset, folder: "level1/level2", scope: @company, created_by: @owner)
    assert { !asset.valid? }
    assert { asset.errors[:folder].present? }
  end

  test "folder rejects spaces" do
    asset = build(:asset, folder: "my folder", scope: @company, created_by: @owner)
    assert { !asset.valid? }
    assert { asset.errors[:folder].present? }
  end

  test "folder allows blank" do
    asset = build(:asset, folder: nil, scope: @company, created_by: @owner)
    assert { asset.valid? }
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

  # ====== merged_for_project ======

  test ".merged_for_project includes company and project assets" do
    create(:asset, name: "a-company.md", scope: @company, created_by: @owner)
    create(:asset, name: "b-project.md", scope: @project, created_by: @owner)

    result = Asset.merged_for_project(@project)
    names = result.map(&:name)

    assert { names.include?("a-company.md") }
    assert { names.include?("b-project.md") }
  end

  test ".merged_for_project sets correct scope_indicators" do
    create(:asset, name: "a-company.md", scope: @company, created_by: @owner)
    create(:asset, name: "b-project.md", scope: @project, created_by: @owner)

    result = Asset.merged_for_project(@project)

    company_asset = result.find { |a| a.name == "a-company.md" }
    project_asset = result.find { |a| a.name == "b-project.md" }

    assert { company_asset.scope_indicator == "company" }
    assert { project_asset.scope_indicator == "project" }
  end

  test ".merged_for_project project overrides company with same name" do
    create(:asset, name: "shared.md", scope: @company, created_by: @owner)
    create(:asset, name: "shared.md", scope: @project, created_by: @owner)

    result = Asset.merged_for_project(@project)
    shared = result.select { |a| a.name == "shared.md" }

    assert { shared.count == 1 }
    assert { shared.first.scope_indicator == "overrides_company" }
    assert { shared.first.scope_type == "Project" }
  end

  test ".merged_for_project excludes other company assets" do
    other_company = create(:company, email_domain: "other-assets.com")
    other_owner = create(:user, :employee, company: other_company)
    create(:asset, name: "other.md", scope: other_company, created_by: other_owner)

    result = Asset.merged_for_project(@project)
    names = result.map(&:name)

    assert { !names.include?("other.md") }
  end

  test ".merged_for_project returns sorted by name" do
    create(:asset, name: "z-asset.md", scope: @company, created_by: @owner)
    create(:asset, name: "a-asset.md", scope: @project, created_by: @owner)

    result = Asset.merged_for_project(@project)
    assert { result.map(&:name) == result.map(&:name).sort }
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

  test ".merged_for_project excludes deleted assets" do
    create(:asset, name: "active.md", scope: @project, created_by: @owner)
    deleted = create(:asset, name: "deleted.md", scope: @company, created_by: @owner)
    deleted.soft_delete!

    result = Asset.merged_for_project(@project)
    names = result.map(&:name)
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
