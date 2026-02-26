# frozen_string_literal: true

require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @project = create(:project, company: @company, owner: create(:user, company: @company))
  end

  test "valid with required attributes" do
    workflow = build(:workflow, scope: @company)
    assert workflow.valid?
  end

  test "invalid without name" do
    workflow = build(:workflow, scope: @company, name: nil)
    assert_not workflow.valid?
    assert_includes workflow.errors[:name], "can't be blank"
  end

  test "invalid without scope" do
    workflow = build(:workflow, scope: nil)
    assert_not workflow.valid?
  end

  test "unique name per scope" do
    create(:workflow, name: "deploy", scope: @company)
    duplicate = build(:workflow, name: "deploy", scope: @company)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "already exists in this scope"
  end

  test "same name allowed in different scopes" do
    create(:workflow, name: "deploy", scope: @company)
    project_workflow = build(:workflow, name: "deploy", scope: @project)
    assert project_workflow.valid?
  end

  test "soft-deleted workflow name can be reused" do
    old = create(:workflow, name: "deploy", scope: @company)
    old.soft_delete!
    new_wf = build(:workflow, name: "deploy", scope: @company)
    assert new_wf.valid?
  end

  test "for_company scope" do
    create(:workflow, scope: @company)
    create(:workflow, scope: @project)
    assert_equal 1, Workflow.for_company(@company).count
  end

  test "for_project scope" do
    create(:workflow, scope: @company)
    create(:workflow, scope: @project)
    assert_equal 1, Workflow.for_project(@project).count
  end

  test "visible_for_project returns company and project workflows" do
    company_wf = create(:workflow, name: "ci", scope: @company)
    project_wf = create(:workflow, name: "deploy", scope: @project)
    merged = Workflow.visible_for_project(@project)
    assert_includes merged, company_wf
    assert_includes merged, project_wf
  end

  test "visible_for_project excludes deleted workflows" do
    wf = create(:workflow, scope: @company)
    wf.soft_delete!
    assert_empty Workflow.visible_for_project(@project)
  end

  test "active scope excludes deleted" do
    wf = create(:workflow, scope: @company)
    wf.soft_delete!
    assert_not_includes Workflow.active, wf
  end

  test "scope_indicator returns company or project" do
    assert_equal "company", build(:workflow, scope: @company).scope_indicator
    assert_equal "project", build(:workflow, scope: @project).scope_indicator
  end

  test "soft_delete sets deleted_at" do
    wf = create(:workflow, scope: @company)
    assert_nil wf.deleted_at
    wf.soft_delete!
    assert_not_nil wf.reload.deleted_at
  end

  test "config defaults to empty hash" do
    wf = create(:workflow, scope: @company)
    assert_equal({}, wf.config)
  end
end
