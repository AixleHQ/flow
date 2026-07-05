# frozen_string_literal: true

require "test_helper"

# Page render-smoke: the project-scoped Aixle Builder controller renders two
# Inertia pages — Projects/AixleBuilder/LandingPage (#show) and
# Projects/AixleBuilder/SessionPage (#show_session). Happy-path render
# contract, complementing aixle_builder_authorization_test.rb (permit/forbid).
class Web::Company::Projects::AixleBuilderRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # eager-loaded collections trip the unused-eager-loading gate
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "show renders the aixle builder landing page with the user's builder sessions" do
    create(:terminal_session, :aixle_builder, project: @project, user: @user)

    get company_project_aixle_builder_path(@project)

    assert_response :success
    assert_inertia_page "Projects/AixleBuilder/LandingPage"
    assert_inertia_props do |props|
      props[:sessions].length == 1
    end
  end

  test "show_session renders the aixle builder session page for an owned builder session" do
    session = create(:terminal_session, :aixle_builder, project: @project, user: @user)

    get company_project_aixle_builder_session_path(@project, session)

    assert_response :success
    assert_inertia_page "Projects/AixleBuilder/SessionPage"
    assert_inertia_props do |props|
      props[:session].present?
    end
  end
end
