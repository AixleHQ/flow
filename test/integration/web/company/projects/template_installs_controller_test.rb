# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::TemplateInstallsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    create(:tool, :system, name: "add_board_comment")
    result = Templates::Installer.new(catalog_template: create_catalog_template, user: @user,
                                      target: { company: @company }, idempotency_key: "k").apply
    @project = result.project
    @install = result.install
    sign_in_as(@user)
  end

  def item(ref) = @install.setup_items.find_by!(ref: ref)

  test "the checklist lists what is left, labelled" do
    get company_project_template_install_path(@project, @install)

    assert_response :success
    assert_inertia_page "Projects/TemplateInstalls/ShowPage"
    assert_inertia_props do |props|
      props[:items].pluck(:label).include?("Add the secret SENTRY_TOKEN") &&
        props[:install][:setup].include?("Connect GitHub first")
    end
  end

  test "a secret added from the checklist is stored and the item is done" do
    patch company_project_template_install_setup_item_path(@project, @install, item("secret:SENTRY_TOKEN")),
          params: { operation: "add_secret", value: "tok-9" }

    assert_redirected_to company_project_template_install_path(@project, @install)
    assert_equal "tok-9", @project.config_items.find_by!(name: "SENTRY_TOKEN").decrypted_value
    assert_equal "done", item("secret:SENTRY_TOKEN").status
  end

  test "a refused activation comes back as an alert" do
    patch company_project_template_install_setup_item_path(@project, @install, item("trigger:1")),
          params: { operation: "activate" }

    assert_redirected_to company_project_template_install_path(@project, @install)
    assert_match(/auto-run/, flash[:alert])
  end

  test "a viewer can read the checklist but not act on it" do
    viewer = create(:user, :viewer, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project.add_collaborator(viewer)
    sign_in_as(viewer)

    patch company_project_template_install_setup_item_path(@project, @install, item("secret:SENTRY_TOKEN")),
          params: { operation: "add_secret", value: "tok-9" }

    assert_nil @project.config_items.find_by(name: "SENTRY_TOKEN")
    assert_equal "You are not authorized to perform this action.", flash[:alert]
  end
end
