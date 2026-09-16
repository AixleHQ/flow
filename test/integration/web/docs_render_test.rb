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

  # The page bodies live in the client bundle and the routable slugs live in
  # Ruby, with nothing connecting the two lists. A page added to the bundle and
  # not to the controller answers 404 — which reads as a missing document rather
  # than a missing line, and is how a freshly written guide went unreachable.
  test "every page in the client bundle is routable" do
    registered = File.read(Rails.root.join("app/frontend/pages/Docs/data/pages/index.ts"))
                     .scan(/^\s*'?([a-z0-9-]+)'?:\s*\{$/).flatten

    assert_operator registered.size, :>, 20, "the registry should have been parsed, not missed"
    assert_empty registered - Web::DocsController::PAGES,
                 "pages in the bundle that the controller will 404"
    assert_empty Web::DocsController::PAGES - registered,
                 "routable slugs with no page behind them"
  end

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
