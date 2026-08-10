# frozen_string_literal: true

require "test_helper"

# Render-smoke request test for Web::OnboardingController (docs/testing.md §2):
# GET the page the controller renders and assert the Inertia component + status.
#
# Auth reality: this controller skips `enforce_onboarding` and adds its own
# `require_auth` (signed-in only). Crucially, `show` REDIRECTS a
# `:onboarding_completed` user to company_projects_path — so, per the guide's
# "match the controller's real auth needs" rule, the persona here is a plain
# signed-in user whose onboarding is still in progress (factory default
# onboarding_state "step1"), NOT `:onboarding_completed`.
#
# Pages covered:
#   - Onboarding/OnboardingPage  (show)
class Web::OnboardingRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    # No :onboarding_completed trait: a completed user would be redirected away.
    @user = create(:user, :admin, company: @company, password: AuthHelper::TEST_PASSWORD)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "show renders the onboarding page" do
    # An active auth-setup session so TerminalSessionResource serialization is
    # exercised during render (factory defaults: session_type auth_setup +
    # state not_started => matches .auth_sessions.active).
    create(:terminal_session, user: @user)

    get onboarding_path

    assert_response :success
    assert_inertia_page "Onboarding/OnboardingPage"
  end

  # The onboarding UI polls the auth session over a PARTIAL reload (the agent step
  # asks for `auth_sessions` alone after creating a session, and again on every
  # cable refresh). inertia_rails filters `only` against the prop names this
  # controller declares — snake_case — BEFORE the camelCase prop transformer runs
  # (config/initializers/inertia.rb), so a client asking for "authSessions"
  # matches nothing and silently gets a response without the prop. That is what
  # left the Connect panel stuck on "Starting auth session..." until a full page
  # reload. Pin both halves: the snake_case key resolves, the camelCase one does not.
  test "the auth_sessions prop is served for a snake_case partial reload" do
    create(:terminal_session, user: @user)

    assert_equal 1, partial_props("auth_sessions").fetch("authSessions").size
    assert_not partial_props("authSessions").key?("authSessions")
  end

  private

  def partial_props(key)
    get onboarding_path, headers: {
      "X-Inertia" => "true",
      "X-Inertia-Partial-Component" => "Onboarding/OnboardingPage",
      "X-Inertia-Partial-Data" => key
    }

    assert_response :success
    JSON.parse(response.body).fetch("props")
  end
end
