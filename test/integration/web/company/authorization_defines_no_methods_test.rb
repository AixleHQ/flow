# frozen_string_literal: true

require "test_helper"

# A method defined from inside a request closes over that request's controller. With YJIT on,
# every such definition stays reachable, so each request kept its whole response in memory and
# production web processes grew until they were OOMKilled.
class Web::Company::AuthorizationDefinesNoMethodsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    create(:project, company: @company, owner: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "an authorized request defines nothing on its controller class" do
    controller = Web::Company::ProjectsController
    methods_before = controller.instance_methods(false).sort

    get company_projects_path

    assert_response :success
    assert_equal methods_before, controller.instance_methods(false).sort
    assert_empty controller.instance_methods(false).grep(/\Aauthorize_/)
  end
end
