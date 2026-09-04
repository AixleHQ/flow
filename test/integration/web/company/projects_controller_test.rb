# frozen_string_literal: true

require "test_helper"

class Web::Company::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders projects page" do
    get company_projects_path
    assert_inertia_page "Projects/IndexPage"
  end

  test "index includes each project's owner/collaborator avatar preview" do
    collaborator = create(:user, :employee, :onboarding_completed, company: @company)
    project = create(:project, company: @company, owner: @user)
    project.add_collaborator(collaborator)

    get company_projects_path

    props_project = inertia.props[:projects].find { |p| p[:id] == project.id }
    assert_equal 2, props_project[:membersCount]
    assert_equal [ @user.id, collaborator.id ], props_project[:members].pluck(:id)
  end

  test "index marks the current user's favorites and lists them first" do
    create(:project, name: "Alpha", company: @company, owner: @user)
    zeta = create(:project, name: "Zeta", company: @company, owner: @user)
    create(:project_favorite, user: @user, project: zeta)

    get company_projects_path

    assert_equal [ "Zeta", "Alpha" ], inertia.props[:projects].pluck(:name)
    assert_equal [ true, false ], inertia.props[:projects].pluck(:favorite)
  end

  test "index favorites are per user — another member's star is not reported or ordered for this user" do
    alpha = create(:project, name: "Alpha", company: @company, owner: @user)
    create(:project, name: "Zeta", company: @company, owner: @user)
    other = create(:user, :employee, :onboarding_completed, company: @company)
    create(:project_favorite, user: other, project: alpha)

    get company_projects_path

    assert_equal [ "Alpha", "Zeta" ], inertia.props[:projects].pluck(:name)
    assert_equal [ false, false ], inertia.props[:projects].pluck(:favorite)
  end

  # The sidebar's "All Projects" list comes from the shared props, not this page,
  # so it is asserted on a page that renders no `projects` prop of its own.
  test "the sidebar project list puts the current user's favorites first" do
    create(:project, name: "Alpha", company: @company, owner: @user)
    zeta = create(:project, name: "Zeta", company: @company, owner: @user)
    create(:project_favorite, user: @user, project: zeta)

    get company_members_path

    assert_equal [ "Zeta", "Alpha" ], inertia.props[:projects].pluck(:name)
  end

  test "create redirects on success" do
    post company_projects_path, params: { project: { name: "Test Project", description: "A test" } }
    assert_response :redirect
  end

  test "destroy redirects on success" do
    project = create(:project, company: @company, owner: @user)
    delete company_project_path(project)
    assert_response :redirect
  end

  # Regression for PALAD-AI-RAILS-2M: bound workflows must not 500 project destroy.
  test "destroy succeeds when a project workflow is bound to a board column" do
    project = create(:project, company: @company, owner: @user)
    board = create(:board, project: project)
    column = create(:board_column, board: board)
    workflow = create(:workflow, scope: project)
    ColumnWorkflowBinding.create!(board_column: column, workflow: workflow, trigger_mode: :manual)

    delete company_project_path(project)

    assert_response :redirect
    assert_not Project.exists?(project.id)
    assert_not Workflow.unscoped.exists?(workflow.id)
    assert_not ColumnWorkflowBinding.exists?(workflow_id: workflow.id)
  end

  test "destroy succeeds for a company admin who is not the project owner" do
    owner = create(:user, :employee, :onboarding_completed, company: @company)
    project = create(:project, company: @company, owner: owner)

    delete company_project_path(project)

    assert_response :redirect
    assert_not Project.exists?(project.id)
  end

  test "destroy succeeds for the project owner who is not an admin" do
    owner = create(:user, :employee, :onboarding_completed, company: @company,
                                                             password: AuthHelper::TEST_PASSWORD)
    project = create(:project, company: @company, owner: owner)
    sign_in_as(owner)

    delete company_project_path(project)

    assert_response :redirect
    assert_not Project.exists?(project.id)
  end

  test "destroy is denied for a collaborator who is neither owner nor admin" do
    owner = create(:user, :employee, :onboarding_completed, company: @company)
    project = create(:project, company: @company, owner: owner)
    collaborator = create(:user, :employee, :onboarding_completed, company: @company,
                                                                    password: AuthHelper::TEST_PASSWORD)
    project.add_collaborator(collaborator)
    sign_in_as(collaborator)

    delete company_project_path(project)

    # Denial UX is a 302 redirect + not-authorized alert (see docs/research design doc, DECISION 1),
    # not a literal 403. The redirect_back falls back to root_path because the test sends no Referer.
    assert_response :redirect
    assert_equal "You are not authorized to perform this action.", flash[:alert]
    assert Project.exists?(project.id)
  end
end
