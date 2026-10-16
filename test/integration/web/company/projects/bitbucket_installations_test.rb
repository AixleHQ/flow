# frozen_string_literal: true

require "test_helper"

# A project's "Install the app" path: a workspace the company bound connects at
# once; any other needs the app installed and Connect pressed in Bitbucket.
class Web::Company::Projects::BitbucketInstallationsTest < ActionDispatch::IntegrationTest
  include ForgeTestHelper

  setup do
    with_bitbucket_settings(app_mode: true)
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "a workspace the company bound connects the project" do
    installation = create(:bitbucket_installation, :bound, :with_token, company: @company, workspace_slug: "acme")
    stub_workspace_repositories(installation)

    post company_project_bitbucket_attach_path(@project), params: { workspace: "https://bitbucket.org/ACME/" }, as: :json

    assert_response :ok
    assert_equal true, response.parsed_body["connected"] # rubocop:disable Minitest/AssertTruthy
    integration = Integration.find(response.parsed_body["integration_id"])
    assert_equal [ @project.id, installation.id, "app" ],
                 [ integration.project_id, integration.bitbucket_installation_id, integration.bitbucket_auth_mode ]
  end

  test "a deployment with no install link still offers the app, and says so" do
    with_bitbucket_settings(app_mode: true, install_url: nil)

    post company_project_bitbucket_attach_path(@project), params: { workspace: "staging-ws" }, as: :json

    assert_equal({ "install_required" => true, "install_url" => nil }, response.parsed_body)
  end

  test "any other workspace answers with the install link and remembers the project for the consent page" do
    create(:bitbucket_installation, :bound, :with_token, company: create(:company), workspace_slug: "elsewhere")

    post company_project_bitbucket_attach_path(@project), params: { workspace: "elsewhere" }, as: :json

    assert_equal({ "install_required" => true, "install_url" => BitbucketTestHelper::FORGE_INSTALL_URL }, response.parsed_body)
    get bitbucket_connect_path
    assert_inertia_props { |props| assert_equal @project.id, props[:preselectedProjectId] }
  end

  test "nothing is offered while app mode is not configured" do
    with_bitbucket_settings(app_mode: false)

    post company_project_bitbucket_attach_path(@project), params: { workspace: "acme" }, as: :json

    assert_response :not_found
  end
end
