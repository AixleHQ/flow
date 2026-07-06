# frozen_string_literal: true

require "test_helper"

class Web::SessionsRenderTest < ActionDispatch::IntegrationTest
  # Auth/LoginPage (SessionsController#new) renders only for a guest — a
  # signed-in user is redirected to projects/onboarding — so this smoke test
  # intentionally does NOT sign in and needs no prerequisite data.
  setup do
    Bullet.enable = false
  end
  teardown { Bullet.enable = true }

  test "new renders the login page for a guest" do
    get login_path

    assert_response :success
    assert_inertia_page "Auth/LoginPage"
  end

  test "new surfaces the error param as a prop" do
    get login_path(error: "oauth_failed")

    assert_inertia_page "Auth/LoginPage"
    assert_inertia_props error: "oauth_failed"
  end
end
