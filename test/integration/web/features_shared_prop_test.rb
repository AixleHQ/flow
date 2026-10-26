# frozen_string_literal: true

require "test_helper"

# The `features` shared prop is the only way a page learns about flags, so it
# must carry the client flags as the backend resolves them and nothing else.
# FeaturesResource takes its attributes from the shipped registry, so this runs
# against config/feature_flags.yml: external_runners (client) and coder_reap (not).
class Web::FeaturesSharedPropTest < ActionDispatch::IntegrationTest
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

    client_keys = FeatureFlags.registry.definitions.select(&:client?).map { |d| d.key.to_s.camelize(:lower) }
    assert_equal client_keys.sort, features.to_h.keys.sort
    refute features["externalRunners"]
    assert_not features.key?("coderReap")
    assert_not features.key?("coder_reap")
  end

  test "a company override is what that company's users see" do
    company = signed_in_company

    with_feature(:external_runners, true, company: company) do
      assert features_prop(company_projects_path)["externalRunners"]
    end
  end

  test "another company's override does not leak" do
    signed_in_company
    other = create(:company)

    with_feature(:external_runners, true, company: other) do
      refute features_prop(company_projects_path)["externalRunners"]
    end
  end

  test "an anonymous page gets the client flags at their global value" do
    with_feature(:external_runners, true) do
      features = features_prop(login_path)

      assert features["externalRunners"]
    end
  end

  test "a partial reload that does not ask for features still re-evaluates them" do
    company = signed_in_company

    page = inertia_props(company_projects_path)
    refute page.dig("props", "features", "externalRunners")

    with_feature(:external_runners, true, company: company) do
      props = inertia_props(company_projects_path, only: "flash", component: page.fetch("component")).fetch("props")

      assert_not props.key?("settings"), "the reload should have been partial"
      assert props.dig("features", "externalRunners")
    end
  end
end
