# frozen_string_literal: true

require "test_helper"

# Where we host, a company made from the admin either pays — the allowance, then
# a card, like a self-serve signup — or is one we carry, which pays nothing and
# runs at a number only we set.
class Admin::CompanyBillingTermsTest < ActionDispatch::IntegrationTest
  setup do
    @operator = create(:user, :super_admin, :onboarding_completed, company: create(:company),
                       password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@operator)
    with_mode(Deployment::SAAS)
  end

  def with_mode(mode)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  def create_company(**attributes)
    post admin_companies_path, params: {
      company: { name: "Tuesday", email_domain: "tuesday.example" }.merge(attributes)
    }
    Company.find_by(email_domain: "tuesday.example")
  end

  test "a company made here pays: it starts on the allowance, at the limit it was given" do
    company = create_company(session_concurrency_limit: "3")

    assert_equal "trialing", company.billing_state
    assert_equal false, company.managed_by_aixle # rubocop:disable Minitest/RefuteFalse
    assert_equal 3, SessionConcurrencyLimit.for_company(company.id)
  end

  # No limit means nothing is metered, so a paying company without one would
  # run for free.
  test "a paying company is refused without a limit" do
    assert_no_difference("Company.count") do
      create_company(session_concurrency_limit: "")
    end

    assert_response :unprocessable_entity
    assert_match(/required for a company that pays/, response.body)
  end

  test "a company we carry is not billed and gets two workers" do
    company = create_company(managed_by_aixle: "1", session_concurrency_limit: "")

    assert company.managed_by_aixle
    assert_equal "active", company.billing_state
    assert_equal Company::MANAGED_SESSION_LIMIT, SessionConcurrencyLimit.for_company(company.id)
  end

  test "a company we carry keeps a limit the operator chose" do
    company = create_company(managed_by_aixle: "1", session_concurrency_limit: "5")

    assert_equal 5, SessionConcurrencyLimit.for_company(company.id)
  end

  # Nobody is invoiced on a self-hosted installation, so a company made there
  # stays as it always was.
  test "outside the hosted product a company is made as before" do
    with_mode(Deployment::SELF_HOSTED)

    company = create_company

    assert_equal "active", company.billing_state
    assert_nil SessionConcurrencyLimit.for_company(company.id)
  end

  test "ticking an existing company as ours takes it off the allowance" do
    company = create(:company, :trialing)

    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, managed_by_aixle: "1" }
    }

    company.reload
    assert company.managed_by_aixle
    assert_equal "active", company.billing_state
  end
end
