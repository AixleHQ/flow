# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project Teams page
# (Web::Company::Projects::TeamsPolicy): anyone who reaches the project reads it;
# only the project owner and company admins change teams, since a team decides
# whose agent subscription runs spend, as a trigger's Runs as does.
class Web::Company::Projects::TeamsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  MANAGE = {
    owner: :allowed_write, admin: :allowed_write, collaborator: :denied,
    viewer: :denied, stranger: :not_found, foreign_admin: :not_found
  }.freeze

  setup do
    setup_project_authz_personas
    @team = create(:project_team, project: @project)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_teams_path(@project) }
  end

  test "create is for the owner and company admins" do
    assert_role_matrix(MANAGE, transport: :web) do
      post company_project_teams_path(@project), params: { team: { name: "T #{SecureRandom.hex(3)}", member_ids: [] } }
    end
  end

  test "update is for the owner and company admins" do
    assert_role_matrix(MANAGE, transport: :web) do
      patch company_project_team_path(@project, @team), params: { team: { name: "Renamed #{SecureRandom.hex(3)}" } }
    end
  end

  test "destroy is for the owner and company admins" do
    assert_role_matrix(MANAGE, transport: :web) do
      delete company_project_team_path(@project, create(:project_team, project: @project))
    end
  end
end
