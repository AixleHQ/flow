# frozen_string_literal: true

require "test_helper"

# Where the browser may report to PostHog, and how a person's answer is kept.
# The server decides: the page only ever loads analytics when this prop is set.
class Web::AnalyticsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @company = create(:company)
    @user = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
  end

  def analytics_prop
    captured = :unset
    assert_inertia_props do |props|
      captured = props[:analytics]
      true
    end
    captured
  end

  test "self-hosted, or hosted with no key, shares nothing to load" do
    sign_in_as(@user)
    get company_projects_path
    assert_nil analytics_prop

    enable_analytics!(api_key: nil)
    get company_projects_path
    assert_nil analytics_prop
  end

  test "the hosted product shares the key and the company context, not who the person is beyond an id" do
    enable_analytics!
    sign_in_as(@user)

    get company_projects_path

    prop = analytics_prop
    assert_equal "phc_test", prop[:key]
    assert_equal true, prop[:capture] # rubocop:disable Minitest/AssertTruthy
    assert_nil prop[:consent]
    assert_equal @user.id.to_s, prop[:distinctId]
    assert_equal @company.id, prop[:context][:companyId]
    assert_not_includes prop.to_json, @user.email
  end

  test "nothing is shared while a super admin impersonates" do
    enable_analytics!
    operator = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(operator)
    post impersonate_admin_user_path(@user)

    get company_projects_path

    assert_nil analytics_prop
  end

  test "pages whose URL is a credential ask for consent but never capture" do
    enable_analytics!
    get magic_link_path(token: "not-a-real-token")
    assert_equal false, analytics_prop[:capture] # rubocop:disable Minitest/RefuteFalse

    get edit_password_reset_path(token: "not-a-real-token")
    assert_equal false, analytics_prop[:capture] # rubocop:disable Minitest/RefuteFalse
  end

  test "a signed-in answer is kept on the account" do
    enable_analytics!
    sign_in_as(@user)

    patch analytics_consent_path, params: { consent: "granted" }

    assert_equal "granted", @user.reload.analytics_consent
    assert_not_nil @user.analytics_consent_at

    patch analytics_consent_path, params: { consent: "denied" }
    assert_equal "denied", @user.reload.analytics_consent
  end

  test "someone signed in who has no workspace yet can still answer" do
    enable_analytics!
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: true))
    newcomer = create(:user, email: "dana@acme-robotics.example", password: AuthHelper::TEST_PASSWORD)
    sign_in_as(newcomer)

    patch analytics_consent_path, params: { consent: "denied" }

    assert_response :see_other
    assert_equal "denied", newcomer.reload.analytics_consent
  end

  test "an answer that is not one of the two is refused" do
    sign_in_as(@user)

    patch analytics_consent_path, params: { consent: "maybe" }

    assert_response :unprocessable_content
    assert_nil @user.reload.analytics_consent
  end

  test "an operator impersonating someone may not answer for them" do
    operator = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(operator)
    post impersonate_admin_user_path(@user)

    patch analytics_consent_path, params: { consent: "granted" }

    assert_response :forbidden
    assert_nil @user.reload.analytics_consent
  end

  test "an answer given before signing in is adopted at sign-in, and never overrides one already given" do
    cookies[Analytics::CONSENT_COOKIE] = "granted"
    sign_in_as(@user)
    get company_projects_path
    assert_equal "granted", @user.reload.analytics_consent

    cookies[Analytics::CONSENT_COOKIE] = "denied"
    get company_projects_path
    assert_equal "granted", @user.reload.analytics_consent
  end

  test "Profile → Privacy shows the current answer" do
    enable_analytics!
    @user.record_analytics_consent!("denied")
    sign_in_as(@user)

    get privacy_profile_path

    assert_inertia_page "Profile/Privacy"
    assert_inertia_props do |props|
      assert_equal "denied", props[:analyticsConsent]
      assert props[:analyticsAvailable]
    end
  end
end
