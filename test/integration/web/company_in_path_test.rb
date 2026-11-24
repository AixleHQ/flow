# frozen_string_literal: true

require "test_helper"

# A company page names its company in the path (/company/<slug>/…), so each tab
# stays in its own whatever another tab opened, and a link says where it goes.
class Web::CompanyInPathTest < ActionDispatch::IntegrationTest
  setup do
    @company_a = create(:company)
    @company_b = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company_a, password: AuthHelper::TEST_PASSWORD)
    @user.company_memberships.find_by!(company: @company_a).update!(accepted_at: 2.days.ago)
    create(:company_membership, :admin, user: @user, company: @company_b, accepted_at: 1.day.ago,
                                        onboarding_state: "completed", onboarding_completed_at: Time.current,
                                        position: "engineering", preferred_agent_language: "en")
    @project_b = create(:project, company: @company_b, owner: @user)
    sign_in_as(@user)
  end

  def shown_company_id
    inertia.props[:currentUser][:currentCompany][:id]
  end

  test "each page shows the company its path names, whichever was opened last" do
    get company_projects_path(company_slug: @company_b.slug)
    assert_equal @company_b.id, shown_company_id

    get company_projects_path(company_slug: @company_a.slug)
    assert_equal @company_a.id, shown_company_id

    get company_members_path(company_slug: @company_b.slug)
    assert_equal @company_b.id, shown_company_id
  end

  test "a write lands in the company its path names, not the one opened last" do
    get company_projects_path(company_slug: @company_b.slug)

    post company_members_path(company_slug: @company_a.slug), params: {
      user: { email: "new.member@example.com", name: "New Member", role: "employee" }
    }

    invited = User.find_by!(email: "new.member@example.com")
    assert_equal [ @company_a.id ], invited.company_memberships.pluck(:company_id)
  end

  test "a company the person does not belong to is not found" do
    stranger = create(:company)

    get company_projects_path(company_slug: stranger.slug)
    assert_response :not_found

    post company_members_path(company_slug: stranger.slug), params: { user: { email: "x@example.com", name: "X", role: "employee" } }
    assert_response :not_found
    assert_nil User.find_by(email: "x@example.com")
  end

  test "a project opened under another company's slug goes to the same page under its own" do
    get company_project_board_path(@project_b, company_slug: @company_a.slug, n: 3)
    assert_redirected_to company_project_board_path(@project_b, company_slug: @company_b.slug, n: 3)

    post company_project_workflows_path(@project_b, company_slug: @company_a.slug), params: { workflow: { name: "Nope" } }
    assert_response :not_found
  end

  test "an unscoped link opens the same page in the company last used" do
    get company_projects_path(company_slug: @company_b.slug)

    get "/company/members?tab=pending"
    assert_redirected_to "/company/#{@company_b.slug}/members?tab=pending"

    get "/company"
    assert_redirected_to "/company/#{@company_b.slug}/projects"

    get "/user/#{@user.id}"
    assert_redirected_to "/company/#{@company_b.slug}/user/#{@user.id}"
  end

  test "an unscoped link to a project opens it in the project's company" do
    get company_projects_path(company_slug: @company_a.slug)

    get "/company/projects/#{@project_b.id}/board"
    assert_redirected_to "/company/#{@company_b.slug}/projects/#{@project_b.id}/board"
  end

  test "an unscoped write is passed on with its method" do
    post "/company/members", params: { user: { email: "late@example.com", name: "Late", role: "employee" } }
    assert_response :temporary_redirect
    assert_equal "/company/#{@company_a.slug}/members", URI(response.location).path

    post "/api/v1/company/folders", params: { path: "docs" }, as: :json
    assert_response :temporary_redirect
    assert_equal "/api/v1/company/#{@company_a.slug}/folders", URI(response.location).path
  end

  test "a path under a company that names no page is not found rather than passed on" do
    get "/company/#{@company_a.slug}/no-such-page"
    assert_response :not_found
  end

  test "an unscoped link opened signed out goes to the sign-in page" do
    delete logout_path

    get "/company/members"
    assert_redirected_to login_path
  end
end
