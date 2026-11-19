# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders members page" do
    get company_project_members_path(@project)
    assert_inertia_page "Projects/Members/MembersPage"
  end

  test "the collaborator picker only offers ACTIVE members (no invited/revoked leakage)" do
    active = create(:user, :employee, company: @company)
    invited = create(:user, :employee, company: @company, membership_state: "invited")
    revoked = create(:user, :employee, company: @company)
    @company.company_memberships.find_by!(user: revoked).revoke!

    get company_project_members_path(@project)

    ids = inertia.props[:companyUsers].map { |u| u[:id] }
    assert_includes ids, active.id
    assert_not_includes ids, invited.id
    assert_not_includes ids, revoked.id
  end

  # A project from another of the user's companies lists its own company's members,
  # not the session company's, and collaborators are looked up there too.
  test "a project from the user's other company lists and adds that company's members" do
    other = create(:company)
    create(:company_membership, user: @user, company: other, role: "admin", accepted_at: Time.current,
                                onboarding_state: "completed", onboarding_completed_at: Time.current)
    other_project = create(:project, company: other, owner: @user)
    colleague = create(:user, :employee, company: other)
    session_company_member = create(:user, :employee, company: @company)

    get company_project_members_path(other_project)

    ids = inertia.props[:companyUsers].map { |u| u[:id] }
    assert_includes ids, colleague.id
    assert_not_includes ids, session_company_member.id

    post company_project_members_path(other_project),
         params: { collaborator: { user_ids: [ colleague.id, session_company_member.id ] } }
    assert_response :not_found
    assert_not other_project.project_collaborators.exists?(user_id: colleague.id)

    get company_projects_path
    assert_equal other.id, session[:current_company_id]
  end

  test "a non-active member cannot be added as collaborator" do
    invited = create(:user, :employee, company: @company, membership_state: "invited")

    post company_project_members_path(@project), params: { collaborator: { user_ids: [ invited.id ] } }

    assert_response :not_found
    assert_not @project.project_collaborators.exists?(user_id: invited.id)
  end

  test "create adds every picked user to the project at once" do
    first = create(:user, :employee, company: @company)
    second = create(:user, :employee, company: @company)

    post company_project_members_path(@project), params: { collaborator: { user_ids: [ first.id, second.id ] } }

    assert_redirected_to company_project_members_path(@project)
    assert_equal [ first.id, second.id ].sort, @project.project_collaborators.pluck(:user_id).sort
    assert_equal "2 members added to project", flash[:notice]
  end

  test "create names the one user it added" do
    member = create(:user, :employee, company: @company, name: "Bo Member")

    post company_project_members_path(@project), params: { collaborator: { user_ids: [ member.id ] } }

    assert @project.project_collaborators.exists?(user_id: member.id)
    assert_equal "Bo Member added to project", flash[:notice]
  end

  test "create adds nobody when one of the picked users cannot join" do
    member = create(:user, :employee, company: @company)

    assert_no_difference -> { ProjectCollaborator.count } do
      post company_project_members_path(@project), params: { collaborator: { user_ids: [ member.id, @user.id ] } }
    end

    assert_redirected_to company_project_members_path(@project)
  end

  test "create still takes the single user_id an older page posts" do
    member = create(:user, :employee, company: @company)

    post company_project_members_path(@project), params: { collaborator: { user_id: member.id } }

    assert_redirected_to company_project_members_path(@project)
    assert @project.project_collaborators.exists?(user_id: member.id)
  end

  test "create without any picked user is a bad request" do
    post company_project_members_path(@project), params: { collaborator: { user_ids: [] } }, as: :json

    assert_response :bad_request
  end

  test "destroy removes collaborator and redirects" do
    member = create(:user, company: @company)
    create(:project_collaborator, project: @project, user: member)

    delete company_project_member_path(@project, member)
    assert_response :redirect
  end
end
