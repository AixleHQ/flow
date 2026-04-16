# frozen_string_literal: true

require "test_helper"

class Web::PagesControllerTest < ActionDispatch::IntegrationTest
  # Non-Inertia: layout web/legal — no assert_inertia_page.

  test "privacy_policy renders" do
    get privacy_policy_path
    assert_response :success
  end

  test "terms_of_service renders" do
    get terms_of_service_path
    assert_response :success
  end
end
