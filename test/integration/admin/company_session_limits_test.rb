# frozen_string_literal: true

require "test_helper"

# A company's session limit is the number the installation sells, so it is set
# where a company is administered rather than on the queue's own page. It is
# stored as a SessionConcurrencyLimit row and reached through a virtual attribute
# on Company, which is what lets the admin form carry it like any other field.
class Admin::CompanySessionLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @admin = create(:user, :super_admin, :onboarding_completed, company: @company,
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
    with_admission(project: 1)
  end

  def limit_row
    SessionConcurrencyLimit.find_by(scope_type: "Company", scope_id: @company.id)
  end

  test "the show page reports the company's limit" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 12)

    get admin_company_path(@company)

    assert_response :success
    assert_match(/12/, response.body)
  end

  test "setting a limit writes the row" do
    patch admin_company_path(@company), params: {
      company: { name: @company.name, email_domain: @company.email_domain, session_concurrency_limit: "9" }
    }

    assert_equal 9, limit_row&.max_sessions
  end

  test "changing a limit moves the policy revision so pools recompute their cap" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 4)
    before = SessionAdmissionPolicy.current.revision

    patch admin_company_path(@company), params: {
      company: { name: @company.name, email_domain: @company.email_domain, session_concurrency_limit: "6" }
    }

    assert_equal 6, limit_row&.max_sessions
    assert_operator SessionAdmissionPolicy.current.revision, :>, before
  end

  # Blank is the exemption, not a limit of zero: the company becomes unbounded,
  # and unbilled.
  test "clearing the field removes the limit rather than setting it to zero" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 4)

    patch admin_company_path(@company), params: {
      company: { name: @company.name, email_domain: @company.email_domain, session_concurrency_limit: "" }
    }

    assert_nil limit_row
    assert_nil SessionConcurrencyLimit.for_company(@company.id)
  end

  test "a value that is not a positive whole number is refused on the company" do
    patch admin_company_path(@company), params: {
      company: { name: @company.name, email_domain: @company.email_domain, session_concurrency_limit: "0" }
    }

    assert_nil limit_row, "nothing may be written when the form is refused"
  end

  # Every other update of a company has to leave the limit alone, or saving a
  # logo would silently exempt the customer from billing.
  test "an update that does not submit the field leaves the limit untouched" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 4)

    @company.update!(display_name: "Renamed")

    assert_equal 4, limit_row&.max_sessions
  end
end
