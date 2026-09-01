# frozen_string_literal: true

require "test_helper"

# Render-smoke request test for Web::DocsController (docs/testing.md §2):
# GET each page the controller renders and assert the Inertia component + status.
#
# Docs is a PUBLIC controller: it inherits no `authenticate_user!` guard and
# explicitly skips `enforce_onboarding` + `redirect_super_admin_to_admin_panel`,
# so it renders for anyone (signed out included) — matched here per the guide's
# "public pages match the controller's real auth needs" rule (cf. pages_controller_test).
#
# Pages covered:
#   - Docs/DocsPage  (show)
class Web::DocsRenderTest < ActionDispatch::IntegrationTest
  setup do
    Bullet.enable = false # keep parity with the render-smoke suite; docs itself issues no queries
  end

  teardown { Bullet.enable = true }

  test "show renders the docs page with the default slug" do
    get docs_path
    assert_response :success
    assert_inertia_page "Docs/DocsPage"
    assert_inertia_props do |props|
      props[:slug] == "user-guide"
    end
  end

  test "show renders the docs page for a known slug" do
    get docs_page_path("agents")
    assert_response :success
    assert_inertia_page "Docs/DocsPage"
    assert_inertia_props do |props|
      props[:slug] == "agents"
    end
  end

  test "show renders the product-area snapshot pages" do
    %w[user-guide-outline changelog-product-areas].each do |slug|
      get docs_page_path(slug)
      assert_response :success
      assert_inertia_page "Docs/DocsPage"
      assert_inertia_props { |props| props[:slug] == slug }
    end
  end
end
