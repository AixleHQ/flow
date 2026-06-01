# frozen_string_literal: true

require "test_helper"

class Web::Company::WorkflowTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @admin = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @member = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @other_member = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @admin)
    @workflow = create(:workflow, scope: @project)
    create_list(:step, 2, workflow: @workflow)
    sign_in_as(@admin)
  end

  test "index renders template catalog page" do
    template = create(:workflow_template, company: @company, owner: @admin)
    version = create(:workflow_template_version, workflow_template: template)
    template.update!(current_version: version)

    get company_workflow_templates_path
    assert_inertia_page "Company/WorkflowTemplates/IndexPage"
    assert_inertia_props do |props|
      props[:projects].any? { |p| p[:id] == @project.id }
    end
  end

  test "index filters templates by name" do
    create(:workflow_template, company: @company, owner: @admin, name: "Alpha Flow")
    create(:workflow_template, company: @company, owner: @admin, name: "Beta Flow")

    get company_workflow_templates_path, params: { q: { name_cont: "Alpha" } }
    assert_inertia_page "Company/WorkflowTemplates/IndexPage"
    assert_inertia_props do |props|
      props[:templates].size == 1 && props[:templates].first[:name] == "Alpha Flow"
    end
  end

  test "create publishes template from workflow" do
    post company_workflow_templates_path, params: {
      workflow_template: {
        name: "Published Flow",
        description: "Desc",
        use_case: "Dev",
        visibility: "company",
        source_workflow_id: @workflow.id
      }
    }

    assert_response :redirect
    assert_equal 1, WorkflowTemplate.count
    version = WorkflowTemplateVersion.last
    assert_equal @workflow.id, version.source_workflow_id
  end

  test "owner can update template metadata" do
    template = create(:workflow_template, company: @company, owner: @admin, name: "Old name")

    patch company_workflow_template_path(template), params: {
      workflow_template: { name: "New name", description: "Updated", use_case: "QA", visibility: "private" }
    }

    assert_response :redirect
    template.reload
    assert_equal "New name", template.name
    assert_equal "private", template.visibility
  end

  test "non-owner member cannot update template" do
    template = create(:workflow_template, company: @company, owner: @admin)
    sign_in_as(@other_member)

    patch company_workflow_template_path(template), params: {
      workflow_template: { name: "Hijacked" }
    }

    assert_response :redirect
    assert_equal template.name, template.reload.name
  end

  test "admin can update another users template" do
    template = create(:workflow_template, company: @company, owner: @member, name: "Member template")

    patch company_workflow_template_path(template), params: {
      workflow_template: { name: "Admin renamed" }
    }

    assert_response :redirect
    assert_equal "Admin renamed", template.reload.name
  end

  test "owner can publish new version" do
    template = create(:workflow_template, company: @company, owner: @admin)
    version = create(:workflow_template_version, workflow_template: template, version_number: 1, source_workflow: @workflow)
    template.update!(current_version: version)

    post publish_version_company_workflow_template_path(template), params: {
      source_workflow_id: @workflow.id,
      changelog: "Added review step"
    }

    assert_response :redirect
    template.reload
    assert_equal 2, template.current_version.version_number
    assert_equal "Added review step", template.current_version.changelog
    assert_equal @workflow.id, template.current_version.source_workflow_id
  end

  test "non-owner cannot publish new version" do
    template = create(:workflow_template, company: @company, owner: @admin)
    version = create(:workflow_template_version, workflow_template: template, source_workflow: @workflow)
    template.update!(current_version: version)
    sign_in_as(@other_member)

    post publish_version_company_workflow_template_path(template), params: {
      source_workflow_id: @workflow.id,
      changelog: "Nope"
    }

    assert_response :redirect
    assert_equal 1, template.versions.count
  end

  test "private template hidden from other members on index" do
    create(:workflow_template, company: @company, owner: @admin, name: "Secret", visibility: "private")
    create(:workflow_template, company: @company, owner: @admin, name: "Public", visibility: "company")
    sign_in_as(@other_member)

    get company_workflow_templates_path
    assert_inertia_props do |props|
      props[:templates].size == 1 && props[:templates].first[:name] == "Public"
    end
  end

  test "create rejects workflow from inaccessible project" do
    private_project = create(:project, company: @company, owner: @other_member)
    private_workflow = create(:workflow, scope: private_project)
    sign_in_as(@member)

    assert_no_difference "WorkflowTemplate.count" do
      post company_workflow_templates_path, params: {
        workflow_template: {
          name: "Stolen Flow",
          source_workflow_id: private_workflow.id
        }
      }
    end

    assert_response :redirect
  end

  test "create shows friendly error for duplicate template name" do
    create(:workflow_template, company: @company, owner: @admin, name: "Existing Flow")

    assert_no_difference "WorkflowTemplate.count" do
      post company_workflow_templates_path, params: {
        workflow_template: {
          name: "Existing Flow",
          source_workflow_id: @workflow.id
        }
      }
    end

    assert_response :redirect
    assert_match(/already exists/, flash[:alert])
  end
end
