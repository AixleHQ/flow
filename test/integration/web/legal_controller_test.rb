# frozen_string_literal: true

require "test_helper"

class Web::LegalControllerTest < ActionDispatch::IntegrationTest
  # Non-Inertia: layout web/legal — no assert_inertia_page.

  def with_mode(mode)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  test "the hosted product publishes every document, each at its current version" do
    with_mode(Deployment::SAAS)

    {
      legal_terms_of_service_path => "Aixle Standard Terms and Conditions",
      legal_terms_of_use_path => "Aixle User Terms of Use",
      legal_privacy_policy_path => "Privacy Policy"
    }.each do |path, heading|
      get path

      assert_response :success
      assert_select "h1", heading
    end
    assert_select ".legal-meta", /Last updated #{LegalDocument::PRIVACY_POLICY.updated_on.strftime("%B %-d, %Y")}/
  end

  test "pages say whether there are documents to link" do
    with_mode(Deployment::SAAS)
    get login_path, headers: { "X-Inertia" => "true" }
    assert_equal true, response.parsed_body.dig("props", "settings", "legalPages") # rubocop:disable Minitest/AssertTruthy

    with_mode(Deployment::SELF_HOSTED)
    get login_path, headers: { "X-Inertia" => "true" }
    assert_equal false, response.parsed_body.dig("props", "settings", "legalPages") # rubocop:disable Minitest/RefuteFalse
  end

  test "the index lists the documents" do
    with_mode(Deployment::SAAS)

    get legal_path

    assert_response :success
    assert_select ".legal-documents a", LegalDocument::ALL.size
  end

  test "the Terms of Service point at the documents where they are published" do
    with_mode(Deployment::SAAS)

    get legal_terms_of_service_path

    assert_select "a[href='https://flow.aixle.com/legal/terms_of_use']"
    assert_select "a[href='https://flow.aixle.com/legal/terms_of_service']"
    assert_select "#exhibit-b", /Data Processing Addendum/
    assert_select "#exhibit-c", /Business Associate Agreement/
  end

  test "they can be read by somebody who has not accepted them yet" do
    with_mode(Deployment::SAAS)
    Settings.stubs(:legal).returns(Hashie::Mash.new(acceptance_required: true))
    sign_in_as(create(:user, :onboarding_completed, company: create(:company),
                                                    password: AuthHelper::TEST_PASSWORD,
                                                    password_confirmation: AuthHelper::TEST_PASSWORD))

    get legal_terms_of_use_path

    assert_response :success
  end

  test "an installation we do not host publishes none of them" do
    [ Deployment::SELF_HOSTED, Deployment::AWS_MARKETPLACE ].each do |mode|
      with_mode(mode)

      [ legal_path, legal_terms_of_service_path, legal_terms_of_use_path, legal_privacy_policy_path ].each do |path|
        get path

        assert_response :not_found, "#{path} in #{mode}"
      end
    end
  end

  test "the old addresses lead to the new ones" do
    get "/privacy-policy"
    assert_redirected_to "/legal/privacy_policy"

    get "/terms-of-service"
    assert_redirected_to "/legal/terms_of_service"
  end
end
