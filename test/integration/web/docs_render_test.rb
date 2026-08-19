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

  # The product guide is a second, user-facing section of the same portal. Its slugs
  # are registered in three places that can drift apart (the controller allow-list,
  # the page registry, and the nav); the frontend guards its own two, this covers
  # the controller's.
  PRODUCT_GUIDE_SLUGS = %w[
    using-flow getting-started project-home tasks running-workflows starting-work
    sessions-and-runs assets personas agent-capabilities repositories ai-builder
    people-and-access secrets analytics company-workspace examples
  ].freeze

  test "show renders every product guide page" do
    PRODUCT_GUIDE_SLUGS.each do |slug|
      get docs_page_path(slug)
      assert_response :success, "expected /docs/#{slug} to render"
      assert_inertia_page "Docs/DocsPage"
      assert_inertia_props do |props|
        props[:slug] == slug
      end
    end
  end

  test "show answers 404 for a slug the portal does not publish" do
    get docs_page_path("no-such-page")
    assert_response :not_found
    # Still the docs page, so the reader lands on the portal's own not-found view
    # rather than the generic error page.
    assert_inertia_component "Docs/DocsPage"
  end
end
