# frozen_string_literal: true

require "test_helper"

class ProjectFavoriteTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, :onboarding_completed, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  test "a member can favorite a project" do
    favorite = ProjectFavorite.new(user: @owner, project: @project)

    assert favorite.valid?, favorite.errors.full_messages.to_sentence
  end

  test "the same user cannot favorite the same project twice" do
    create(:project_favorite, user: @owner, project: @project)

    duplicate = ProjectFavorite.new(user: @owner, project: @project)

    assert_not duplicate.valid?
    assert_includes duplicate.errors.full_messages.to_sentence, "already a favorite"
  end

  test "two users favoriting the same project are independent rows" do
    other = create(:user, :employee, :onboarding_completed, company: @company)

    create(:project_favorite, user: @owner, project: @project)
    second = ProjectFavorite.new(user: other, project: @project)

    assert second.valid?, second.errors.full_messages.to_sentence
    assert second.save
    assert_equal 2, @project.project_favorites.count
  end

  test "a user with no active membership in the project's company cannot favorite it" do
    outsider = create(:user, :employee, :onboarding_completed, company: create(:company))

    favorite = ProjectFavorite.new(user: outsider, project: @project)

    assert_not favorite.valid?
    assert_includes favorite.errors.full_messages.to_sentence, "same company"
  end

  test "destroying the project removes its favorites" do
    create(:project_favorite, user: @owner, project: @project)

    assert_difference("ProjectFavorite.count", -1) { @project.destroy! }
  end

  test "destroying the user removes their favorites" do
    member = create(:user, :employee, :onboarding_completed, company: @company)
    create(:project_favorite, user: member, project: @project)

    assert_difference("ProjectFavorite.count", -1) { member.destroy! }
  end
end
