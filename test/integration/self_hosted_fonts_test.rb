# frozen_string_literal: true

require "test_helper"

# Every page Flow renders gets its fonts from /fonts/v1/, never from Google (#353).
class SelfHostedFontsTest < ActionDispatch::IntegrationTest
  GOOGLE_FONT_HOSTS = /googleapis|gstatic/

  def assert_self_hosted_fonts(page)
    assert_no_match GOOGLE_FONT_HOSTS, response.body, "#{page} still loads from Google"
    assert_includes response.body, %(href="/fonts/v1/fonts.css"), "#{page} does not link the self-hosted fonts"
  end

  test "the landing page, a legal page and the app load the self-hosted fonts" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))

    { "landing page" => root_path, "privacy policy" => legal_privacy_policy_path, "login" => login_path }.each do |page, path|
      get path

      assert_response :success
      assert_self_hosted_fonts(page)
    end
  end

  test "the admin panel loads the self-hosted fonts" do
    admin = create(:user, :super_admin, :onboarding_completed, company: create(:company),
                   password: AuthHelper::TEST_PASSWORD)
    sign_in_as(admin)

    get admin_users_path

    assert_response :success
    assert_self_hosted_fonts("admin panel")
  end

  test "the not-found page loads the self-hosted fonts" do
    config = Rails.application.env_config
    saved = config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    config.merge!("action_dispatch.show_exceptions" => :all, "action_dispatch.show_detailed_exceptions" => false)
    get "/no/such/page"

    assert_response :not_found
    assert_self_hosted_fonts("not-found page")
  ensure
    config.merge!(saved)
  end

  test "the public asset viewer loads the self-hosted fonts" do
    user = create(:user, :with_company)
    project = create(:project, company: user.companies.first, owner: user)
    asset = create(:asset, scope: project, created_by: user, name: "page.html")
    create(:asset_version, asset: asset, uploaded_by: user, content_type: "text/html",
                           file: AssetFileUploader.upload(StringIO.new("<b>hi</b>"), :store))
    token = asset.share!

    get public_asset_path(token: token)

    assert_response :success
    assert_self_hosted_fonts("public asset viewer")
  end
end
