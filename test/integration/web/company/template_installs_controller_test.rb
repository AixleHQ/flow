# frozen_string_literal: true

require "test_helper"

class Web::Company::TemplateInstallsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    create(:tool, :system, name: "board_add_comment")
    @template = create_catalog_template
  end

  test "a guest who presses Install signs in and lands back on the version they saw" do
    get new_company_template_install_path(namespace: "acme", slug: "dev-team-sdlc", version: 3)
    assert_redirected_to login_path

    post login_path, params: { email: @user.email, password: AuthHelper::TEST_PASSWORD }

    assert_redirected_to new_company_template_install_path(namespace: "acme", slug: "dev-team-sdlc", version: 3)
  end

  test "the install page renders the plan for a new project" do
    sign_in_as(@user)

    get new_company_template_install_path(namespace: "acme", slug: "dev-team-sdlc", version: 3)

    assert_response :success
    assert_inertia_page "Templates/InstallPage"
    assert_inertia_props do |props|
      props[:plan][:target] == "new_project" && props[:plan][:resolved] && props[:idempotencyKey].present? &&
        props[:projects].empty?
    end
  end

  test "installing creates the project and goes to its setup checklist" do
    sign_in_as(@user)
    plan = Templates::Installer.new(catalog_template: @template, user: @user, target: { company: @company },
                                    idempotency_key: "x").plan

    assert_difference -> { @company.projects.count }, 1 do
      post company_template_installs_path, params: {
        namespace: "acme", slug: "dev-team-sdlc", version: 3, idempotency_key: "page-1", digest: plan.digest,
        inputs: { review_language: "German" }, secrets: { SENTRY_TOKEN: "tok-1" }
      }
    end

    project = @company.projects.order(:id).last
    assert_redirected_to company_project_template_install_path(project, project.template_installs.sole)
    assert_equal "tok-1", project.config_items.find_by!(name: "SENTRY_TOKEN").decrypted_value
  end

  test "a plan that moved since the page was rendered sends the user back to review it" do
    sign_in_as(@user)

    assert_no_difference -> { Project.count } do
      post company_template_installs_path, params: { namespace: "acme", slug: "dev-team-sdlc", version: 3, idempotency_key: "p", digest: "stale" }
    end

    assert_redirected_to new_company_template_install_path(namespace: "acme", slug: "dev-team-sdlc")
    assert_match(/review it again/, flash[:alert])
  end

  test "a viewer cannot open the install page" do
    viewer = create(:user, :viewer, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(viewer)

    get new_company_template_install_path(namespace: "acme", slug: "dev-team-sdlc")

    assert_response :redirect
    assert_equal "You are not authorized to perform this action.", flash[:alert]
  end
end
