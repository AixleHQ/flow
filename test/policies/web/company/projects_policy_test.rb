# frozen_string_literal: true

require "test_helper"

class Web::Company::ProjectsPolicyTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, :onboarding_completed, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  def policy_for(user, id: @project.id)
    params = ActionController::Parameters.new(id: id)
    Web::Company::ProjectsPolicy.new(BaseContext.new(user, params, company: @company), nil)
  end

  test "destroy? is true for the project owner (employee role)" do
    assert policy_for(@owner).destroy?
  end

  test "destroy? is true for a company admin who is not the owner" do
    admin = create(:user, :admin, :onboarding_completed, company: @company)
    assert_not_equal @project.owner_id, admin.id
    assert policy_for(admin).destroy?
  end

  test "destroy? is false for a collaborator who is not owner or admin" do
    collaborator = create(:user, :employee, :onboarding_completed, company: @company)
    @project.add_collaborator(collaborator)
    assert_not policy_for(collaborator).destroy?
  end

  test "destroy? is false for a stranger employee" do
    stranger = create(:user, :employee, :onboarding_completed, company: @company)
    assert_not policy_for(stranger).destroy?
  end

  test "destroy? is false for an admin of another company" do
    other_company = create(:company)
    foreign_admin = create(:user, :admin, :onboarding_completed, company: other_company)
    # current_project is scoped to the user's own company, so a foreign admin
    # cannot resolve this project id -> nil -> false.
    assert_not policy_for(foreign_admin).destroy?
  end

  test "destroy? is false when the project id is unknown" do
    assert_not policy_for(@owner, id: 0).destroy?
  end

  test "destroy? is false when there is no id in params" do
    assert_not policy_for(@owner, id: nil).destroy?
  end

  # Regression guard: tightening destroy? must not change the other actions.
  test "index? and create? remain true; show? is true for an accessible user" do
    policy = policy_for(@owner)
    assert policy.index?
    assert policy.create?
    assert policy.show?
  end
end
