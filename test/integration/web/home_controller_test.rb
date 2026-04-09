# frozen_string_literal: true

require "test_helper"

class Web::HomeControllerTest < ActionDispatch::IntegrationTest
  # Non-Inertia: layout web/landing, empty HTML shell — no assert_inertia_page.
  test "show renders landing for root path" do
    get root_path
    assert_response :success
  end
end
