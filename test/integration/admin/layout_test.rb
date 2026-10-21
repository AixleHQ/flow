# frozen_string_literal: true

require "test_helper"

# Administrate's bundled anchor positioning polyfill swaps the <link> to
# Administrate's stylesheet for a blob: copy on load. Turbo then re-appends the
# original after the skin on the next visit, and every form field turns white
# in the dark scheme. Only a browser shows that; this pins the opt-out that
# prevents it.
class Admin::LayoutTest < ActionDispatch::IntegrationTest
  setup do
    company = create(:company)
    admin = create(:user, :super_admin, :onboarding_completed, company: company,
                   password: AuthHelper::TEST_PASSWORD)
    sign_in_as(admin)
  end

  test "every admin page keeps the anchor polyfill off the stylesheets before Administrate's script loads" do
    get admin_companies_path

    assert_response :success
    opt_out = response.body.index("window.ANCHOR_POSITIONING_POLYFILL_OPTIONS = { elements: [] };")
    administrate_script = response.body.index(%r{<script src="[^"]*/administrate/application-})

    assert opt_out, "the polyfill is told to leave stylesheets alone"
    assert administrate_script, "Administrate's script is on the page"
    assert_operator opt_out, :<, administrate_script
  end
end
