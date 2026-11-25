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
    assert_equal 1, queries.count { |sql| sql.match?(/FROM "workflow_runs"/) },
                 queries.grep(/FROM "workflow_runs"/).inspect
  end

  test "builder renders workflow builder" do
    wf = create(:workflow, scope: @project)

    get builder_company_project_workflow_path(@project, wf)
    assert_inertia_page "Projects/Workflows/BuilderPage"
  end

  test "builder carries the saved workflow's data-flow issues" do
    wf = create(:workflow, scope: @project)
    create(:step, workflow: wf, name: "Report", instructions: "Fill in {{artifact_name}}.")

    get builder_company_project_workflow_path(@project, wf)

    assert_inertia_props do |props|
      props[:issues].map { |issue| [ issue[:code], issue[:severity], issue[:token] ] } ==
        [ [ "unknown_braces", "warning", "{{artifact_name}}" ] ]
    end
  end

  test "builder of a live workflow names its open draft and what starts it" do
    wf = create(:workflow, scope: @project, name: "Release")
    create(:step, workflow: wf, allow_non_interactive: true)
    column = create(:board_column, board: create(:board, project: @project))
    ColumnWorkflowBinding.create!(board_column: column, workflow: wf, trigger_mode: :auto, cooldown_seconds: 0)
    create(:trigger_binding, project: @project, workflow: wf, enabled: false)
    draft = WorkflowDrafts.open!(wf, actor: Versions::Actor.ui(@user))

    get builder_company_project_workflow_path(@project, wf)

    assert_inertia_props(activeTriggerCount: 1, draftOf: nil)
    assert_equal [ draft.id, @user.name ], inertia.props[:draft].values_at("id", "updatedBy")
  end

  test "the draft page opens the draft in the builder, and the draft's own id leads there" do
    wf = create(:workflow, scope: @project, name: "Release")
    create(:step, workflow: wf, name: "Build")
    draft = WorkflowDrafts.open!(wf, actor: Versions::Actor.ui(@user))

    get draft_company_project_workflow_path(@project, wf)

    assert_inertia_page "Projects/Workflows/BuilderPage"
    assert_inertia_props(draft: nil, activeTriggerCount: 0, readOnly: false)
    assert_equal draft.id, inertia.props[:workflow]["id"]
    assert_equal [ wf.id, "Release", 1, 1 ],
                 inertia.props[:draftOf].values_at("id", "name", "currentVersionNumber", "baseVersionNumber")
    assert_equal [ "Build" ], inertia.props[:steps].pluck("name")

    get builder_company_project_workflow_path(@project, draft)
    assert_redirected_to draft_company_project_workflow_path(@project, wf)
  end

  test "the draft page of a workflow without a draft goes back to its builder" do
    wf = create(:workflow, scope: @project)

    get draft_company_project_workflow_path(@project, wf)

    assert_redirected_to builder_company_project_workflow_path(@project, wf)
  end

  test "drafts stay out of the workflow list and its archive" do
    wf = create(:workflow, scope: @project, name: "Release")
    WorkflowDrafts.discard!(WorkflowDrafts.open!(wf, actor: Versions::Actor.ui(@user)), actor: Versions::Actor.ui(@user))
    WorkflowDrafts.open!(wf, actor: Versions::Actor.ui(@user))

    get company_project_workflows_path(@project)

    assert_equal [ wf.id ], inertia.props[:workflows].pluck("id")
    assert_empty inertia.props[:archivedWorkflows]
  end

  test "builder is read-only for a project viewer" do
    viewer = create(:user, :viewer, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD,
                                                           email: "client-#{SecureRandom.hex(3)}@external.com")
    @project.add_collaborator(viewer)
    wf = create(:workflow, scope: @project)
    sign_in_as(viewer)

    get builder_company_project_workflow_path(@project, wf)

    assert_inertia_props(readOnly: true)
  end

  test "builder opens an archived workflow read-only, with the sessions it was archived with" do
    wf = create(:workflow, scope: @project, name: "Old pipeline")
    create(:step, workflow: wf, name: "Review")
    Versions.archive!(wf, actor: Versions::Actor.ui(@user))

    get builder_company_project_workflow_path(@project, wf)

    assert_inertia_page "Projects/Workflows/BuilderPage"
    assert_inertia_props(readOnly: true)
    assert_equal [ "Review" ], inertia.props[:steps].pluck("name")
    assert inertia.props[:workflow]["archivedAt"].present?
  end

  test "builder lists every tracker, detached ones too, and whether each recognises a mention of Aixle" do
    integration = create(:integration, :azure_devops, :active, company: @company, project: @project, connected_by: @user)
    create(:project_tracker, integration: integration, handle: "boards", status: "detached")
    wf = create(:workflow, scope: @project)

    get builder_company_project_workflow_path(@project, wf)

    assert_inertia_props do |props|
      props[:trackers].map { |t| [ t[:handle], t[:status], t[:mentionsRecognized] ] } == [ [ "boards", "detached", false ] ]
    end
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

  test "builder and index offer the project's AWS roles and no other project's" do
    wf = create(:workflow, scope: @project)
    role = create(:aws_oidc_role, name: "prod-diag", role_arn: "arn:aws:iam::123456789012:role/prod-diag",
                                  region: "eu-west-1",
                                  integration: create(:integration, :aws_oidc, company: @company, project: @project))
    create(:aws_oidc_role)
    pages = { builder_company_project_workflow_path(@project, wf) => "Projects/Workflows/BuilderPage",
              company_project_workflows_path(@project) => "Projects/Workflows/WorkflowsPage" }

    pages.each do |path, component|
      assert_equal [ { "id" => role.id, "name" => "prod-diag", "roleArn" => "arn:aws:iam::123456789012:role/prod-diag",
                       "accountId" => "123456789012", "region" => "eu-west-1" } ],
                   deferred_prop(path, component: component, key: "awsOidcRoles")
    end
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

  # The UI deletes the one way the API does: softly, keeping the run history, and
  # reporting a refusal instead of success.
  test "an archived workflow leaves the list for the archived view" do
    workflow = create(:workflow, scope: @project, name: "Old pipeline")
    Versions.archive!(workflow, actor: Versions::Actor.ui(@user))

    get company_project_workflows_path(@project)

    assert_not_includes inertia.props[:workflows].pluck(:id), workflow.id
    archived = inertia.props[:archivedWorkflows]
    assert_equal [ [ workflow.id, "Old pipeline" ] ], archived.map { |w| w.values_at("id", "name") }
    assert archived.first["archivedAt"].present?
  end

  test "destroy keeps the run history and refuses while a run is live" do
    wf = create(:workflow, scope: @project)
    run = create(:workflow_run, :running, workflow: wf, project: @project, user: @user)

    delete company_project_workflow_path(@project, wf)
    assert_match(/active runs/, flash[:alert])
    assert_nil wf.reload.deleted_at

    run.update_column(:state, "completed")
    delete company_project_workflow_path(@project, wf)
    assert wf.reload.deleted_at
    assert WorkflowRun.exists?(run.id)
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
