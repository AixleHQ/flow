# frozen_string_literal: true

require "test_helper"

class Web::Company::TemplateInstallsPolicyTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, :onboarding_completed, company: @company)
    @project = create(:project, company: @company, owner: @owner)
  end

  def company_policy(user) = Web::Company::TemplateInstallsPolicy.new(BaseContext.new(user, {}, company: @company), nil)
  def project_policy(user) = Web::Company::TemplateInstallsPolicy.new(ProjectContext.new(user, {}, project: @project), nil)

  test "employees and admins may install; viewers and outsiders may not" do
    admin = create(:user, :admin, :onboarding_completed, company: @company)
    viewer = create(:user, :viewer, :onboarding_completed, company: @company)
    outsider = create(:user, :employee, :onboarding_completed, company: create(:company))

    assert company_policy(@owner).create?
    assert company_policy(admin).new?
    assert_not company_policy(viewer).create?
    assert_not company_policy(outsider).create?
  end

  test "installing into a project needs write access to that project" do
    collaborator = create(:user, :employee, :onboarding_completed, company: @company)
    @project.add_collaborator(collaborator)
    stranger = create(:user, :employee, :onboarding_completed, company: @company)

    assert project_policy(@owner).install_into_project?
    assert project_policy(collaborator).install_into_project?
    assert_not project_policy(stranger).install_into_project?
  end
end
