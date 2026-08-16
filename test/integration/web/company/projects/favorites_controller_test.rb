# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::FavoritesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, name: "Zeta", company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "create favorites the project for the current user" do
    assert_difference("ProjectFavorite.count", 1) do
      post company_project_favorite_path(@project)
    end

    assert_response :redirect
    assert @user.favorite_projects.exists?(@project.id)
  end

  test "create is idempotent — favoriting twice keeps one row" do
    post company_project_favorite_path(@project)

    assert_no_difference("ProjectFavorite.count") do
      post company_project_favorite_path(@project)
    end

    assert_response :redirect
  end

  test "destroy unfavorites the project" do
    create(:project_favorite, user: @user, project: @project)

    assert_difference("ProjectFavorite.count", -1) do
      delete company_project_favorite_path(@project)
    end

    assert_response :redirect
    assert_not @user.reload.favorite_projects.exists?(@project.id)
  end

  test "destroy is idempotent — unfavoriting something unfavorited is not an error" do
    assert_no_difference("ProjectFavorite.count") do
      delete company_project_favorite_path(@project)
    end

    assert_response :redirect
  end

  test "the favorite is per user — one user's star leaves another's untouched" do
    other = create(:user, :employee, :onboarding_completed, company: @company)
    create(:project_favorite, user: other, project: @project)

    delete company_project_favorite_path(@project)

    assert other.favorite_projects.exists?(@project.id), "another user's favorite was removed"
  end

  test "the favorite persists across sessions" do
    post company_project_favorite_path(@project)
    reset!
    sign_in_as(@user)

    get company_projects_path

    assert_equal true, inertia.props[:projects].find { |p| p[:id] == @project.id }[:favorite]
  end

  test "a project the user cannot reach cannot be favorited" do
    other_owner = create(:user, :employee, :onboarding_completed, company: @company)
    stranger = create(:user, :employee, :onboarding_completed,
                      company: @company, password: AuthHelper::TEST_PASSWORD)
    unreachable = create(:project, company: @company, owner: other_owner)
    sign_in_as(stranger)

    assert_no_difference("ProjectFavorite.count") do
      post company_project_favorite_path(unreachable)
    end

    assert_response :not_found
  end
end
