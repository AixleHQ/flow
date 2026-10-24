# frozen_string_literal: true

require "test_helper"

# The `features` shared prop is the only way a page learns about flags, so it
# must carry the client flags as the backend resolves them and nothing else.
class Web::FeaturesSharedPropTest < ActionDispatch::IntegrationTest
  uses_feature_registry FeatureFlagsHelper::EXAMPLE_REGISTRY

  def features_prop(path)
    get path
    captured = {}
    assert_inertia_props do |shared|
      captured[:features] = shared[:features]
      true
    end
    captured[:features]
  end

  def signed_in_company
    user = create(:user, :with_company, :onboarding_completed, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(user)
    user.companies.first
  end

  # An Inertia visit to +path+; with +only+, a partial reload asking for those
  # props alone, as a cable-triggered `router.reload({ only: [...] })` does.
  def inertia_props(path, only: nil, component: nil)
    headers = { "X-Inertia" => "true" }
    headers.merge!("X-Inertia-Partial-Component" => component, "X-Inertia-Partial-Data" => only) if only
    get path, headers: headers

    assert_response :success
    response.parsed_body
  end

  test "a client: false flag never reaches the page" do
    signed_in_company

    features = features_prop(company_projects_path)

    assert_equal({ "boardAiSummary" => false }, features.to_h)
    assert_not features.key?("coderReap")
    assert_not features.key?("coder_reap")
  end

  test "a company override is what that company's users see" do
    company = signed_in_company

    with_feature(:board_ai_summary, true, company: company) do
      assert_equal({ "boardAiSummary" => true }, features_prop(company_projects_path).to_h)
    end
  end

  test "another company's override does not leak" do
    signed_in_company
    other = create(:company)

    with_feature(:board_ai_summary, true, company: other) do
      assert_equal({ "boardAiSummary" => false }, features_prop(company_projects_path).to_h)
    end
  end

  test "an anonymous page gets the client flags at their global value" do
    with_feature(:board_ai_summary, true) do
      features = features_prop(login_path)

      assert_equal({ "boardAiSummary" => true }, features.to_h)
    end
  end

  test "a partial reload that does not ask for features still re-evaluates them" do
    company = signed_in_company

    page = inertia_props(company_projects_path)
    assert_equal({ "boardAiSummary" => false }, page.dig("props", "features"))

    with_feature(:board_ai_summary, true, company: company) do
      props = inertia_props(company_projects_path, only: "flash", component: page.fetch("component")).fetch("props")

      assert_not props.key?("settings"), "the reload should have been partial"
      assert_equal({ "boardAiSummary" => true }, props["features"])
    end
  end
end
