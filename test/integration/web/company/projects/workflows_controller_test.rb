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

  # This page reported an N+1 from production: the steps of every workflow, plus the
  # sub-steps of every step, were fetched one query at a time. The preload makes it two
  # queries whatever the workflow count, so the assertion is on the shape of the load,
  # not on a total that any unrelated change would move.
  test "index loads steps and sub steps in a fixed number of queries" do
    create_list(:workflow, 3, scope: @project).each do |workflow|
      create_list(:step, 2, workflow: workflow).each { |step| create(:sub_step, step: step) }
    end

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql]
    end

    begin
      get company_project_workflows_path(@project)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_response :success
    assert_equal 1, queries.count { |sql| sql.match?(/FROM "steps"/) }, queries.grep(/FROM "steps"/).inspect
    assert_equal 1, queries.count { |sql| sql.match?(/FROM "sub_steps"/) }, queries.grep(/FROM "sub_steps"/).inspect
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

  # The workflows page's Edit dialog PATCHes this path (WorkflowsPage.tsx), and its
  # own Vitest coverage passes on a mocked `router.patch` — so a missing route here
  # looked green on both sides while renaming a workflow in the UI did nothing.
  test "update renames a workflow and edits its description" do
    wf = create(:workflow, scope: @project, name: "Old name", description: "old description")

    patch company_project_workflow_path(@project, wf),
          params: { workflow: { name: "New name", description: "new description" } }
    assert_response :redirect

    wf.reload
    assert_equal "New name", wf.name
    assert_equal "new description", wf.description
  end

  test "update reports validation errors instead of renaming" do
    create(:workflow, scope: @project, name: "Taken")
    wf = create(:workflow, scope: @project, name: "Keeps its name")

    patch company_project_workflow_path(@project, wf), params: { workflow: { name: "Taken" } }
    assert_response :redirect

    assert_equal "Keeps its name", wf.reload.name
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
