# frozen_string_literal: true

require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @project_owner = create(:user, :employee, :onboarding_completed, company: @company)
    @project = create(:project, company: @company, owner: @project_owner)
  end

  test "accessible_by? is true for owner" do
    assert @project.accessible_by?(@project_owner)
  end

  test "accessible_by? is true for collaborator" do
    collaborator = create(:user, :employee, :onboarding_completed, company: @company)
    @project.add_collaborator(collaborator)
    assert @project.accessible_by?(collaborator)
  end

  test "accessible_by? is true for company admin who is not owner or collaborator" do
    admin = create(:user, :admin, :onboarding_completed, company: @company)
    assert_not_equal @project.owner_id, admin.id
    assert @project.accessible_by?(admin)
  end

  test "accessible_by? is false for employee who is not owner or collaborator" do
    stranger = create(:user, :employee, :onboarding_completed, company: @company)
    assert_not @project.accessible_by?(stranger)
  end

  test "accessible_by? is false for admin of another company" do
    other_company = create(:company)
    foreign_admin = create(:user, :admin, :onboarding_completed, company: other_company)
    assert_not @project.accessible_by?(foreign_admin)
  end

  test "admin? is true for the owner" do
    assert @project.admin?(@project_owner)
  end

  test "admin? is false for a collaborator" do
    collaborator = create(:user, :employee, :onboarding_completed, company: @company)
    @project.add_collaborator(collaborator)
    assert_not @project.admin?(collaborator)
  end

  test "admin? is false for a company admin who is not the owner (owner-only)" do
    admin = create(:user, :admin, :onboarding_completed, company: @company)
    assert_not_equal @project.owner_id, admin.id
    assert_not @project.admin?(admin)
  end

  # favorites_first_for is an ORDER BY prefix: `.order(:name)` still decides the
  # order inside each group, so a favorited "Zeta" leads an alphabetical list.
  test "favorites_first_for puts the user's favorites ahead of the chained ordering" do
    trio = create_named_projects("Alpha", "Middle", "Zeta")
    create(:project_favorite, user: @project_owner, project: trio.fetch("Zeta"))

    assert_equal %w[Zeta Alpha Middle], named_projects.favorites_first_for(@project_owner).order(:name).pluck(:name)
  end

  test "favorites_first_for is per user: one user's star does not reorder another list" do
    trio = create_named_projects("Alpha", "Middle", "Zeta")
    other = create(:user, :employee, :onboarding_completed, company: @company)
    create(:project_favorite, user: @project_owner, project: trio.fetch("Zeta"))

    assert_equal %w[Zeta Alpha Middle], named_projects.favorites_first_for(@project_owner).order(:name).pluck(:name)
    assert_equal %w[Alpha Middle Zeta], named_projects.favorites_first_for(other).order(:name).pluck(:name)
  end

  test "favorites_first_for keeps the chained ordering when nothing is favorited" do
    create_named_projects("Alpha", "Middle", "Zeta")

    assert_equal named_projects.order(:name).pluck(:name),
                 named_projects.favorites_first_for(@project_owner).order(:name).pluck(:name)
  end

  private

  def create_named_projects(*names)
    names.index_with { |name| create(:project, name: name, company: @company, owner: @project_owner) }
  end

  # Only the projects a favorites test created, so the setup project's
  # sequence-generated name cannot land between them alphabetically.
  def named_projects
    @company.projects.where(name: %w[Alpha Middle Zeta])
  end
end
