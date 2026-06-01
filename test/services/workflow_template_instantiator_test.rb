# frozen_string_literal: true

require "test_helper"

class WorkflowTemplateInstantiatorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @source = create(:workflow, scope: @company, name: "Snapshot Source")
    create(:step, workflow: @source, position: 1)
    @template = create(:workflow_template, company: @company, owner: @user)
    @version = create(:workflow_template_version, workflow_template: @template, workflow: @source)
    @template.update!(current_version: @version)
  end

  test "instantiates project workflow from template version" do
    workflow = WorkflowTemplateInstantiator.new(
      project: @project,
      version: @version,
      user: @user
    ).instantiate!

    assert_equal "Project", workflow.scope_type
    assert_equal @template.name, workflow.name
    assert_equal 1, @project.workflows.standard.count
    assert_nil @project.reload.workflow_template_version_id
  end

  test "instantiates and tracks origin for new projects" do
    WorkflowTemplateInstantiator.new(
      project: @project,
      version: @version,
      user: @user
    ).instantiate!(set_project_origin: true)

    assert_equal @version.id, @project.reload.workflow_template_version_id
  end

  test "rejects private template for other users" do
    other = create(:user, company: @company)
    @template.update!(visibility: "private", owner: @user)

    assert_raises WorkflowTemplateInstantiator::Error do
      WorkflowTemplateInstantiator.new(project: @project, version: @version, user: other).instantiate!
    end
  end

  test "instantiates with unique name when template already used in project" do
    first = WorkflowTemplateInstantiator.new(project: @project, version: @version, user: @user).instantiate!
    second = WorkflowTemplateInstantiator.new(project: @project, version: @version, user: @user).instantiate!

    assert_equal @template.name, first.name
    assert_equal "#{@template.name} (1)", second.name
  end
end
