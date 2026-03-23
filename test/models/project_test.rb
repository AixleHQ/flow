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
end
