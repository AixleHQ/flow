# frozen_string_literal: true

require "test_helper"

# Page render-smoke: the project-scoped Workflows controller renders two Inertia
# pages — Projects/Workflows/WorkflowsPage (#index) and
# Projects/Workflows/BuilderPage (#builder). Happy-path render contract,
# complementing workflows_authorization_test.rb (permit/forbid matrix).
class Web::Company::Projects::WorkflowsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # list pages trip the unused-eager-loading gate
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the workflows page with the project's workflows" do
    create(:workflow, scope: @project)

    get company_project_workflows_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Workflows/WorkflowsPage"
  end

  test "builder renders the workflow builder page for a project workflow" do
    workflow = create(:workflow, scope: @project)

    get builder_company_project_workflow_path(@project, workflow)

    assert_response :success
    assert_inertia_page "Projects/Workflows/BuilderPage"
  end

  # The run modal preselects this runtime. Without it the modal fell back to the
  # first configured credential — an arbitrary row order, so a member whose
  # default is Claude could get a Cursor run.
  test "index carries the membership's default agent runtime for the run modal" do
    create(:agent_credential, user: @user, company: @company, agent_type: "cursor_cli")
    claude = create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @user.company_memberships.sole.update!(default_agent_credential: claude)

    get company_project_workflows_path(@project)

    assert_inertia_page "Projects/Workflows/WorkflowsPage"
    assert_inertia_props defaultAgentRuntime: "claude_code"
  end

  test "builder carries the membership's default agent runtime for the run modal" do
    workflow = create(:workflow, scope: @project)
    create(:agent_credential, user: @user, company: @company, agent_type: "cursor_cli")
    claude = create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @user.company_memberships.sole.update!(default_agent_credential: claude)

    get builder_company_project_workflow_path(@project, workflow)

    assert_inertia_page "Projects/Workflows/BuilderPage"
    assert_inertia_props defaultAgentRuntime: "claude_code"
  end
end
