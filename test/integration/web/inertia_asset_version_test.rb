# frozen_string_literal: true

require "test_helper"

# config/initializers/inertia.rb leaves the asset version unset in test, so these
# tests set one the way production derives it from the bundle.
class Web::InertiaAssetVersionTest < ActionDispatch::IntegrationTest
  setup do
    @previous_version = InertiaRails.configuration.version
    InertiaRails.configuration.version = "current-bundle"

    company = create(:company)
    user = create(:user, :admin, :onboarding_completed, company: company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(user)
  end

  teardown do
    InertiaRails.configuration.version = @previous_version
  end

  test "a visit from a tab on an older bundle is sent to a full page load" do
    get company_projects_path, headers: { "X-Inertia" => "true", "X-Inertia-Version" => "previous-bundle" }

    assert_response :conflict
    assert_equal company_projects_url, response.headers["X-Inertia-Location"]
  end

  test "a visit from a tab on the current bundle renders the page" do
    get company_projects_path, headers: { "X-Inertia" => "true", "X-Inertia-Version" => "current-bundle" }

    assert_inertia_page "Projects/IndexPage"
  end

  test "a form sent from a tab on an older bundle is still saved" do
    assert_difference -> { Project.count }, 1 do
      post company_projects_path,
           params: { project: { name: "Stale Tab Project" } },
           headers: { "X-Inertia" => "true", "X-Inertia-Version" => "previous-bundle" }
    end
    assert_response :redirect
  end
end
