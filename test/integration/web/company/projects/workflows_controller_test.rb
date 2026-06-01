# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::WorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders project workflows page" do
    create_list(:workflow, 2, scope: @project)

    get company_project_workflows_path(@project)
    assert_inertia_page "Projects/Workflows/WorkflowsPage"
  end

  test "builder renders workflow builder" do
    wf = create(:workflow, scope: @project)

    get builder_company_project_workflow_path(@project, wf)
    assert_inertia_page "Projects/Workflows/BuilderPage"
  end

  test "create redirects on success" do
    post company_project_workflows_path(@project), params: { workflow: { name: "Proj WF", description: "D" } }
    assert_response :redirect
  end

  test "update renames project workflow" do
    wf = create(:workflow, scope: @project, name: "Old Name")

    patch company_project_workflow_path(@project, wf), params: { workflow: { name: "New Name", description: "Updated" } }

    assert_response :redirect
    assert_equal "New Name", wf.reload.name
  end

  test "duplicate redirects to builder with copied workflow" do
    company_wf = create(:workflow, scope: @company, name: "Company WF")
    create(:step, workflow: company_wf, position: 1)

    post duplicate_company_project_workflow_path(@project, company_wf)
    assert_response :redirect

    copy = @project.workflows.standard.find_by(name: "Company WF")
    assert copy
    assert_equal 1, copy.steps.not_deleted.count
  end

  test "from_template creates workflow and redirects to builder" do
    template = create(:workflow_template, company: @company, owner: @user)
    source = create(:workflow, scope: @company, kind: "template_snapshot")
    create(:step, workflow: source, position: 1)
    version = create(:workflow_template_version, workflow_template: template, workflow: source)
    template.update!(current_version: version)

    post from_template_company_project_workflows_path(@project), params: {
      workflow_template_version_id: version.id
    }

    assert_response :redirect
    assert @project.workflows.standard.exists?(name: template.name)
  end

  test "index maps duplicated workflow to owned template by name for republish" do
    workflow = create(:workflow, scope: @project, name: "Dev Pipeline")
    create(:step, workflow: workflow, position: 1)
    WorkflowTemplatePublisher.new(
      source_workflow: workflow,
      user: @user,
      company: @company,
      name: "Dev Pipeline"
    ).publish!

    copy = WorkflowDuplicator.new(workflow, target_scope: @project).duplicate!
    assert_match(/\ADev Pipeline \(\d+\)\z/, copy.name)

    get company_project_workflows_path(@project)
    assert_inertia_props do |props|
      mapping = props[:publishedTemplatesBySource] || props[:published_templates_by_source]
      entry = mapping[copy.id] || mapping[copy.id.to_s]
      entry && entry[:templateId] == WorkflowTemplate.find_by!(name: "Dev Pipeline").id
    end
  end
end
