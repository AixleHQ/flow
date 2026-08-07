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

  # The picker is the only way to put an asset on a workflow step, so a company
  # asset missing here is invisible even though every other surface offers it and
  # the step would happily mount it.
  test "builder offers company assets alongside the project's own" do
    wf = create(:workflow, scope: @project)
    project_asset = create(:asset, scope: @project)
    company_asset = create(:asset, scope: @company)

    names = deferred_prop(builder_company_project_workflow_path(@project, wf),
                          component: "Projects/Workflows/BuilderPage", key: "assets")
             .map { |a| a["name"] }

    assert_includes names, project_asset.name
    assert_includes names, company_asset.name
  end

  test "index offers company assets alongside the project's own" do
    project_asset = create(:asset, scope: @project)
    company_asset = create(:asset, scope: @company)

    names = deferred_prop(company_project_workflows_path(@project),
                          component: "Projects/Workflows/WorkflowsPage", key: "assets")
             .map { |a| a["name"] }

    assert_includes names, project_asset.name
    assert_includes names, company_asset.name
  end

  test "builder does not offer assets from another company" do
    wf = create(:workflow, scope: @project)
    other_company = create(:company)
    outsider = create(:asset, scope: other_company)

    names = deferred_prop(builder_company_project_workflow_path(@project, wf),
                          component: "Projects/Workflows/BuilderPage", key: "assets")
             .map { |a| a["name"] }

    assert_not_includes names, outsider.name
  end

  test "create redirects on success" do
    post company_project_workflows_path(@project), params: { workflow: { name: "Proj WF", description: "D" } }
    assert_response :redirect
  end

  test "destroy redirects on success" do
    wf = create(:workflow, scope: @project)

    delete company_project_workflow_path(@project, wf)
    assert_response :redirect
  end

  test "publish sets published_at on project workflow" do
    wf = create(:workflow, scope: @project)

    post publish_company_project_workflow_path(@project, wf)
    assert_response :redirect

    wf.reload
    assert wf.published?
  end

  test "duplicate creates a copy in same project" do
    wf = create(:workflow, scope: @project, name: "Original")
    create(:step, workflow: wf, position: 1)

    assert_difference "Workflow.count", 1 do
      post duplicate_company_project_workflow_path(@project, wf)
    end

    assert_response :redirect
  end

  private

  # Resource pickers are deferred props: the first render omits them and the client
  # asks again for that group alone. Fetching one means replaying that second
  # request, headers and all — a plain GET returns a page where the key is absent.
  def deferred_prop(path, component:, key:)
    get path, headers: {
      "X-Inertia" => "true",
      "X-Inertia-Partial-Component" => component,
      "X-Inertia-Partial-Data" => key
    }

    assert_response :success
    JSON.parse(response.body).dig("props", key)
  end
end
