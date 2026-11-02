# frozen_string_literal: true

require "test_helper"

class Web::LegalAcceptancesTest < ActionDispatch::IntegrationTest
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    Settings.stubs(:legal).returns(Hashie::Mash.new(acceptance_required: true))
    @company = create(:company)
  end

  def member(*traits)
    create(:user, :onboarding_completed, *traits, company: @company,
                                                  password: AuthHelper::TEST_PASSWORD,
                                                  password_confirmation: AuthHelper::TEST_PASSWORD)
  end

  def accepted(*documents) = documents.to_h { |document| [ document.key, document.version ] }

  def terms_of_use = LegalDocument::TERMS_OF_USE
  def terms_of_service = LegalDocument::TERMS_OF_SERVICE

  test "a member who has not accepted the Terms of Use is held until they do" do
    sign_in_as(member)

    get company_projects_path

    assert_redirected_to legal_acceptance_path
    follow_redirect!
    assert_inertia_page "Legal/AcceptPage"
    assert_inertia_props do |props|
      assert_equal [ terms_of_use.key ], props[:documents].pluck(:key)
      assert_equal @company.branded_name, props[:companyName]
    end
  end

  test "an admin of a company without the current Terms of Service is asked to accept them for it" do
    sign_in_as(member(:admin))

    get legal_acceptance_path

    assert_inertia_props do |props|
      assert_equal [ terms_of_use.key, terms_of_service.key ], props[:documents].pluck(:key)
      assert_equal %w[user company], props[:documents].pluck(:acceptedBy)
    end
  end

  test "accepting records each document at its version, with the evidence, and lets them in" do
    user = member(:admin)
    sign_in_as(user)

    assert_difference "LegalAcceptance.count", 2 do
      post legal_acceptance_path, params: { accepted: accepted(terms_of_use, terms_of_service) },
                                  headers: { "User-Agent" => "Browser/1.0" }
    end

    assert_redirected_to company_projects_path
    tos = LegalAcceptance.find_by!(document: terms_of_service.key)
    assert_equal [ @company, user, terms_of_service.version ], [ tos.company, tos.user, tos.version ]
    tou = LegalAcceptance.find_by!(document: terms_of_use.key)
    assert_nil tou.company
    assert_equal [ "127.0.0.1", "Browser/1.0" ], [ tou.ip_address, tou.user_agent ]

    get company_projects_path
    assert_response :success
  end

  test "one admin's acceptance of the Terms of Service covers the company's other admins" do
    create(:legal_acceptance, :terms_of_service, company: @company)
    other_admin = member(:admin)
    create(:legal_acceptance, user: other_admin)
    sign_in_as(other_admin)

    get company_projects_path

    assert_response :success
  end

  test "a member is never asked about the Terms of Service, accepted or not" do
    user = member
    create(:legal_acceptance, user: user)
    sign_in_as(user)

    get company_projects_path

    assert_response :success
  end

  test "a new version asks again" do
    user = member
    create(:legal_acceptance, user: user, version: "2020-01-01")
    sign_in_as(user)

    get company_projects_path

    assert_redirected_to legal_acceptance_path
  end

  test "a box ticked for a version that has since changed accepts nothing" do
    sign_in_as(member)

    assert_no_difference "LegalAcceptance.count" do
      post legal_acceptance_path, params: { accepted: { terms_of_use.key => "2020-01-01" } }
    end

    assert_redirected_to legal_acceptance_path
    follow_redirect!
    assert_inertia_props { |props| assert_equal Web::LegalAcceptancesController::STALE, props.dig(:errors, :base) }
  end

  test "an admin who accepts only one of the two accepts nothing" do
    sign_in_as(member(:admin))

    assert_no_difference "LegalAcceptance.count" do
      post legal_acceptance_path, params: { accepted: accepted(terms_of_use) }
    end

    assert_redirected_to legal_acceptance_path
  end

  test "the page sends away somebody with nothing left to accept" do
    user = member
    create(:legal_acceptance, user: user)
    sign_in_as(user)

    get legal_acceptance_path

    assert_redirected_to company_projects_path
  end

  test "signing out is still possible while held" do
    sign_in_as(member)

    delete logout_path

    assert_response :redirect
    refute_equal legal_acceptance_path, URI(response.location).path
  end

  test "an operator impersonating somebody is neither held nor able to accept for them" do
    operator = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD,
                                           password_confirmation: AuthHelper::TEST_PASSWORD)
    victim = member
    sign_in_as(operator)
    post impersonate_admin_user_path(victim)

    get company_projects_path
    assert_response :success

    assert_no_difference "LegalAcceptance.count" do
      post legal_acceptance_path, params: { accepted: accepted(terms_of_use) }
    end
  end

  test "an installation we do not host asks nothing" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))
    sign_in_as(member(:admin))

    get company_projects_path

    assert_response :success
  end
end
