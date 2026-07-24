# frozen_string_literal: true

require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @project = create(:project, company: @company, owner: create(:user, company: @company))
  end

  test "valid with required attributes" do
    workflow = build(:workflow, scope: @project)
    assert workflow.valid?
  end

  test "company scope is rejected (workflows are project- or system-scoped)" do
    workflow = build(:workflow, scope: @company)
    assert_not workflow.valid?
    assert_includes workflow.errors[:scope_type], "is not included in the list"
  end

  test "invalid without name" do
    workflow = build(:workflow, scope: @project, name: nil)
    assert_not workflow.valid?
    assert_includes workflow.errors[:name], "can't be blank"
  end

  test "invalid without scope" do
    workflow = build(:workflow, scope: nil)
    assert_not workflow.valid?
  end

  test "unique name per scope" do
    create(:workflow, name: "deploy", scope: @project)
    duplicate = build(:workflow, name: "deploy", scope: @project)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "already exists in this scope"
  end

  test "same name allowed in different scopes" do
    project2 = create(:project, company: @company, owner: create(:user, company: @company))
    create(:workflow, name: "deploy", scope: @project)
    other_workflow = build(:workflow, name: "deploy", scope: project2)
    assert other_workflow.valid?
  end

  test "soft-deleted workflow name can be reused" do
    old = create(:workflow, name: "deploy", scope: @project)
    old.soft_delete!
    new_wf = build(:workflow, name: "deploy", scope: @project)
    assert new_wf.valid?
  end

  test "belonging_to_company scope returns workflows of all company projects" do
    project2 = create(:project, company: @company, owner: create(:user, company: @company))
    create(:workflow, scope: @project)
    create(:workflow, scope: project2)
    assert_equal 2, Workflow.belonging_to_company(@company).count
  end

  test "for_project scope" do
    project2 = create(:project, company: @company, owner: create(:user, company: @company))
    create(:workflow, scope: @project)
    create(:workflow, scope: project2)
    assert_equal 1, Workflow.for_project(@project).count
  end

  test "visible_for_project returns only that project's workflows" do
    project2 = create(:project, company: @company, owner: create(:user, company: @company))
    mine = create(:workflow, name: "deploy", scope: @project)
    other = create(:workflow, name: "ci", scope: project2)
    merged = Workflow.visible_for_project(@project)
    assert_includes merged, mine
    refute_includes merged, other
  end

  test "visible_for_project excludes deleted workflows" do
    wf = create(:workflow, scope: @project)
    wf.soft_delete!
    assert_empty Workflow.visible_for_project(@project)
  end

  test "active scope excludes deleted" do
    wf = create(:workflow, scope: @project)
    wf.soft_delete!
    assert_not_includes Workflow.active, wf
  end

  test "scope_indicator returns system or project" do
    assert_equal "system", build(:workflow, :system).scope_indicator
    assert_equal "project", build(:workflow, scope: @project).scope_indicator
  end

  test "soft_delete sets deleted_at" do
    wf = create(:workflow, scope: @project)
    assert_nil wf.deleted_at
    wf.soft_delete!
    assert_not_nil wf.reload.deleted_at
  end

  test "config defaults to empty hash" do
    wf = create(:workflow, scope: @project)
    assert_equal({}, wf.config)
  end
end
