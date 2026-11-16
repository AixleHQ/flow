# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::TeamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @anna = create(:user, :employee, :onboarding_completed, company: @company, name: "Anna",
                                                             password: AuthHelper::TEST_PASSWORD)
    @project.add_collaborator(@anna)
    create(:agent_credential, user: @anna, company: @company, agent_type: "kiro_cli")
  end

  test "lists teams with their members, and who could join" do
    team = ProjectTeams::Management.new(project: @project, actor: @owner).create!(name: "Planner", member_ids: [ @anna.id ])
    @owner.update!(exclude_from_teams: true)
    sign_in_as(@owner)

    get company_project_teams_path(@project)

    assert_inertia_page "Projects/Teams/TeamsPage"
    listed = inertia.props[:teams].sole
    assert_equal [ team.id, "Planner", "priority" ], listed.values_at(:id, :name, :strategy)
    assert_equal [ "Kiro CLI" ], listed[:members].sole[:runtimes].map { |runtime| runtime[:label] }
    assert_equal "ready", listed[:members].sole[:status][:state]
    assert_equal @anna.id, listed[:nextMemberId]
    candidates = inertia.props[:candidates].index_by { |candidate| candidate[:id] }
    assert candidates[@anna.id][:agentConnected]
    assert candidates[@owner.id][:excludedFromTeams]
    assert inertia.props[:canManage]
  end

  test "a member whose login expired is listed as signed out, with what to do" do
    ProjectTeams::Management.new(project: @project, actor: @owner).create!(name: "Planner", member_ids: [ @anna.id ])
    AgentCredential.find_by!(user: @anna).update!(status: :error)
    sign_in_as(@owner)

    get company_project_teams_path(@project)

    member = inertia.props[:teams].sole[:members].sole
    assert_equal({ "state" => "signed_out", "until" => nil,
                   "detail" => "Kiro CLI login expired — sign in again in Profile settings" }, member[:status])
    assert_nil inertia.props[:teams].sole[:nextMemberId]
  end

  test "the owner creates and edits a team" do
    sign_in_as(@owner)

    post company_project_teams_path(@project), params: { team: { name: "Planner", strategy: "round_robin", member_ids: [ @anna.id ] } }
    team = @project.project_teams.sole
    assert_redirected_to company_project_teams_path(@project)
    assert_equal [ @anna ], team.members.to_a
    assert team.round_robin?

    patch company_project_team_path(@project, team), params: { team: { name: "Planners", member_ids: [] } }, as: :json
    assert_equal "Planners", team.reload.name
    assert_empty team.members
  end

  test "a bad team comes back as a form error" do
    sign_in_as(@owner)
    outsider = create(:user, :employee, company: @company)

    post company_project_teams_path(@project), params: { team: { name: "Planner", member_ids: [ outsider.id ] } }

    assert_redirected_to company_project_teams_path(@project)
    assert_equal 0, @project.project_teams.count
  end

  test "a team a trigger runs as is not deleted" do
    team = create(:project_team, project: @project)
    create(:trigger_binding, project: @project, workflow: create(:workflow, scope: @project), created_by: @owner,
                             event_type: "webhook.deploy", run_as_team: team)
    sign_in_as(@owner)

    delete company_project_team_path(@project, team)

    assert_match(/run.* as/, flash[:alert])
    assert ProjectTeam.exists?(team.id)
  end

  test "a member leaves a team they are in, even without the right to manage it" do
    team = ProjectTeams::Management.new(project: @project, actor: @owner).create!(name: "Planner", member_ids: [ @anna.id ])
    sign_in_as(@anna)

    delete leave_company_project_team_path(@project, team)

    assert_empty team.reload.members
  end
end
