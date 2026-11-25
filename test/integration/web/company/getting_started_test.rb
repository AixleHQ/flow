# frozen_string_literal: true

require "test_helper"

# Getting started and the product tour's server side (docs/design/product-tour.md).
class Web::Company::GettingStartedTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
  end

  def member(role)
    create(:user, role, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
  end

  def membership_of(user) = user.company_memberships.find_by!(company: @company)

  def publish_hello_flow
    create_catalog_template.update!(**ProductTour::HELLO_FLOW)
  end

  test "a member who has not finished their tour lands on getting started after sign-in" do
    user = member(:employee)

    with_feature(:product_tour, true) do
      sign_in_as(user)
      assert_redirected_to company_getting_started_path(company_slug: @company.slug)

      membership_of(user).finish_product_tour!("a")
      get login_path
      assert_redirected_to company_projects_path(company_slug: @company.slug)
    end
  end

  test "without the flag a member lands on projects and getting started is not there" do
    user = member(:employee)

    with_feature(:product_tour, false) do
      sign_in_as(user)
      assert_redirected_to company_projects_path(company_slug: @company.slug)

      get company_getting_started_path(company_slug: @company.slug)
      assert_response :not_found
    end
  end

  test "completing onboarding opens getting started" do
    user = create(:user, :employee, company: @company, password: AuthHelper::TEST_PASSWORD,
                                    onboarding_state: "step2", position: "engineering", preferred_agent_language: "en")
    create(:agent_credential, user: user, company: @company)

    with_feature(:product_tour, true) do
      sign_in_as(user)
      membership_of(user).update!(onboarding_state: "completed", onboarding_completed_at: Time.current)

      get onboarding_path
      assert_redirected_to company_getting_started_path(company_slug: @company.slug)
    end
  end

  test "the page says whether hello flow is in the catalog and whether the member has a project" do
    user = member(:employee)
    sign_in_as(user)

    with_feature(:product_tour, true) do
      get company_getting_started_path(company_slug: @company.slug)
      assert_inertia_page "GettingStarted/GettingStartedPage"
      assert_inertia_props { |props| props[:helloFlowAvailable] == false && props[:hasProjects] == false }

      publish_hello_flow
      create(:project, company: @company, owner: user)

      get company_getting_started_path(company_slug: @company.slug)
      assert_inertia_props do |props|
        props[:helloFlowAvailable] == true && props[:hasProjects] == true &&
          props[:helloFlowPath] == "/templates/aixle/hello-flow" &&
          props.dig(:currentUser, :productTour) ==
            { variant: "a", aFinished: false, bFinished: false, helloFlowAvailable: true }
      end
    end
  end

  test "a viewer sees the page and is offered tour B" do
    sign_in_as(member(:viewer))

    with_feature(:product_tour, true) do
      get company_getting_started_path(company_slug: @company.slug)

      assert_response :success
      assert_inertia_props { |props| props.dig(:currentUser, :productTour, :variant) == "b" }
    end
  end

  test "build with AI opens AI Builder in a new project when the member has none" do
    user = member(:employee)
    create(:project, company: @company, owner: member(:employee), name: "New Project")
    sign_in_as(user)

    with_feature(:product_tour, true) do
      assert_difference -> { @company.projects.count }, 1 do
        post company_getting_started_build_with_ai_path(company_slug: @company.slug)
      end
    end

    project = @company.projects.order(:created_at).last
    assert_equal [ "New Project 2", user ], [ project.name, project.owner ]
    assert_redirected_to company_project_aixle_builder_path(project, company_slug: @company.slug)
  end

  test "build with AI reuses the member's newest project" do
    user = member(:employee)
    create(:project, company: @company, owner: user, created_at: 2.days.ago)
    newest = create(:project, company: @company, owner: user)
    sign_in_as(user)

    with_feature(:product_tour, true) do
      assert_no_difference -> { Project.count } do
        post company_getting_started_build_with_ai_path(company_slug: @company.slug)
      end
    end

    assert_redirected_to company_project_aixle_builder_path(newest, company_slug: @company.slug)
  end

  test "a viewer cannot build with AI" do
    sign_in_as(member(:viewer))

    with_feature(:product_tour, true) do
      assert_no_difference -> { Project.count } do
        post company_getting_started_build_with_ai_path(company_slug: @company.slug),
             headers: { "Referer" => company_getting_started_url(company_slug: @company.slug) }
      end
    end

    assert_equal "You are not authorized to perform this action.", flash[:alert]
  end

  test "finishing a tour stamps only the current membership, twice is harmless, and a viewer may" do
    user = member(:viewer)
    other_company = create(:company)
    create(:company_membership, :viewer, user: user, company: other_company,
                                         onboarding_state: "completed", onboarding_completed_at: Time.current)
    sign_in_as(user)

    with_feature(:product_tour, true) do
      2.times do
        patch company_product_tour_path(company_slug: @company.slug), params: { variant: "b" }
        assert_response :no_content
      end

      patch company_product_tour_path(company_slug: @company.slug), params: { variant: "x" }
      assert_response :unprocessable_entity
    end

    assert membership_of(user).product_tour_finished?("b")
    assert_not user.company_memberships.find_by!(company: other_company).product_tour_finished?("b")
  end
end
