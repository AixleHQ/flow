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

  # The trial runs one worker, so the number typed — or none — is not the one it
  # gets; a company that needs more is one we carry.
  test "a company made here pays: it starts on the trial, on one worker" do
    company = create_company(session_concurrency_limit: "3")

    assert_equal "trialing", company.billing_state
    assert_equal false, company.managed_by_aixle # rubocop:disable Minitest/RefuteFalse
    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
  end

  test "a company made here without a number starts on one worker too" do
    company = create_company(session_concurrency_limit: "")

    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
  end

  test "a trialing company cannot be given more than one worker, by us either" do
    company = create(:company, :trialing)

    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, session_concurrency_limit: "5" }
    }

    assert_response :unprocessable_entity
    assert_match(/one until a card is added — tick Managed by Aixle to set another/, response.body)
    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
  end

  test "ticking Managed by Aixle frees a trialing company's workers" do
    company = create(:company, :trialing)

    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, managed_by_aixle: "1",
                 session_concurrency_limit: "5" }
    }

    company.reload
    assert_equal "active", company.billing_state
    assert_equal 5, SessionConcurrencyLimit.for_company(company.id)
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

  test "unticking a company we carry puts it on the allowance, where it can add a card" do
    company = create(:company, :managed_by_aixle, session_concurrency_limit: "2")

    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, managed_by_aixle: "0",
                 session_concurrency_limit: "2" }
    }

    company.reload
    assert_equal false, company.managed_by_aixle # rubocop:disable Minitest/RefuteFalse
    assert_equal "trialing", company.billing_state
    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
  end

  test "a company we carry moves onto a trial that ends on the last day set with it" do
    company = create(:company, :managed_by_aixle, session_concurrency_limit: "2")
    CompanyCapacityUsage.record!(company_id: company.id, period_start: 40.days.ago.beginning_of_hour,
                                 quantity_seconds: 2000 * 3600)
    last_day = 14.days.from_now.to_date

    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, managed_by_aixle: "0",
                 session_concurrency_limit: "2", trial_last_day: last_day.iso8601 }
    }

    company.reload
    assert company.billing_trialing?
    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
    assert_equal last_day, Billing::Trial.last_day(company)
  end

  test "an operator puts a company on a trial that ends on a day they choose" do
    company = create(:company, session_concurrency_limit: "4")
    last_day = 10.days.from_now.to_date

    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, trial_last_day: last_day.iso8601 }
    }

    assert_redirected_to admin_company_path(company)
    assert_match(/is on a trial until the end of #{Regexp.escape(last_day.strftime("%B %-d, %Y"))}, on one worker/, flash[:notice])
    company.reload
    assert company.billing_trialing?
    assert_equal last_day, Billing::Trial.last_day(company)
  end

  def set_trial_last_day(company, day)
    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, trial_last_day: day.iso8601 }
    }
  end

  test "an operator gives a company whose trial ended a new one" do
    company = create(:company, billing_state: "blocked", billing_block_reason: "allowance",
                               session_concurrency_limit: "1")
    CompanyCapacityUsage.record!(company_id: company.id, period_start: 3.days.ago.beginning_of_hour,
                                 quantity_seconds: 720 * 3600)
    last_day = 14.days.from_now.to_date

    set_trial_last_day(company, last_day)

    assert_redirected_to admin_company_path(company)
    company.reload
    assert company.billing_trialing?
    assert_nil company.billing_block_reason
    assert_equal 0, Billing::Trial.used_seconds(company)
    assert_equal last_day, Billing::Trial.last_day(company)
  end

  test "an operator extends a trial under way to a later day, or brings it closer" do
    company = create(:company, :trialing, session_concurrency_limit: "1", trial_started_at: 5.days.ago)
    started = company.reload.trial_started_at

    set_trial_last_day(company, 40.days.from_now.to_date)
    assert_equal 40.days.from_now.to_date, Billing::Trial.last_day(company.reload)

    set_trial_last_day(company, 3.days.from_now.to_date)
    company.reload
    assert_equal 3.days.from_now.to_date, Billing::Trial.last_day(company)
    assert_equal started, company.trial_started_at
  end

  test "a trial for a company we carry is refused on the form" do
    company = create(:company, :managed_by_aixle, session_concurrency_limit: "2")

    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, trial_last_day: Date.tomorrow.iso8601 }
    }

    assert_response :unprocessable_entity
    assert_match(/untick Managed by Aixle/, response.body)
    assert company.reload.billing_active?
  end

  test "the company page says when its trial ends" do
    company = create(:company, :trialing)

    get admin_company_path(company)

    assert_response :success
    assert_match(/30 days left, on one worker/, response.body)
  end

  test "unticking a company we carry that has no limit puts it on one worker" do
    company = create(:company, :managed_by_aixle)

    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, managed_by_aixle: "0",
                 session_concurrency_limit: "" }
    }

    company.reload
    assert company.billing_trialing?
    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
  end

  test "unticking a company we carry gives it a fresh trial however much it ran" do
    company = create(:company, :managed_by_aixle, session_concurrency_limit: "2")
    CompanyCapacityUsage.record!(company_id: company.id, period_start: 40.days.ago.beginning_of_hour,
                                 quantity_seconds: 2000 * 3600)

    patch admin_company_path(company), params: {
      company: { name: company.name, email_domain: company.email_domain, managed_by_aixle: "0",
                 session_concurrency_limit: "2" }
    }

    assert_match(/is on a trial until the end of .+, on one worker/, flash[:notice])
    company.reload
    assert company.billing_trialing?
    assert_equal 0, Billing::Trial.used_seconds(company)
    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
  end
end
