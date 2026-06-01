# frozen_string_literal: true

require "test_helper"

class WorkflowTemplatePublisherTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project, name: "Dev Pipeline")
    create(:step, workflow: @workflow, position: 1)
    create(:step, workflow: @workflow, position: 2)
  end

  test "publish creates template and immutable version" do
    template = WorkflowTemplatePublisher.new(
      source_workflow: @workflow,
      user: @user,
      company: @company,
      name: "Dev Pipeline Template",
      description: "Standard dev flow",
      use_case: "Feature work"
    ).publish!

    assert_equal 1, template.versions.count
    assert_equal "Dev Pipeline Template", template.name
    assert_equal "template_snapshot", template.current_version.workflow.kind
    assert_equal 2, template.current_version.workflow.steps.not_deleted.count
  end

  test "republish creates new version without changing old snapshot" do
    template = WorkflowTemplatePublisher.new(
      source_workflow: @workflow,
      user: @user,
      company: @company,
      name: "Dev Pipeline Template"
    ).publish!

    old_version_id = template.current_version_id
    create(:step, workflow: @workflow, position: 3)

    WorkflowTemplatePublisher.new(
      source_workflow: @workflow,
      user: @user,
      company: @company,
      name: "Dev Pipeline Template",
      workflow_template: template
    ).publish!

    template.reload
    assert_equal 2, template.versions.count
    refute_equal old_version_id, template.current_version_id
    assert_equal 2, WorkflowTemplateVersion.find(old_version_id).workflow.steps.not_deleted.count
    assert_equal 3, template.current_version.workflow.steps.not_deleted.count
  end

  test "rejects duplicate template name on create" do
    create(:workflow_template, company: @company, owner: @user, name: "Dev Pipeline")

    error = assert_raises(WorkflowTemplatePublisher::Error) do
      WorkflowTemplatePublisher.new(
        source_workflow: @workflow,
        user: @user,
        company: @company,
        name: "Dev Pipeline"
      ).publish!
    end

    assert_match(/already exists/, error.message)
    assert_match(/Publish new version/, error.message)
  end

  test "rejects duplicate template name for non-owner with generic message" do
    create(:workflow_template, company: @company, owner: @user, name: "Dev Pipeline")
    other = create(:user, company: @company)
    company_workflow = create(:workflow, scope: @company, name: "Company Flow")

    error = assert_raises(WorkflowTemplatePublisher::Error) do
      WorkflowTemplatePublisher.new(
        source_workflow: company_workflow,
        user: other,
        company: @company,
        name: "Dev Pipeline"
      ).publish!
    end

    assert_match(/already exists in your company catalog/, error.message)
    assert_no_match(/Publish new version/, error.message)
  end
end
