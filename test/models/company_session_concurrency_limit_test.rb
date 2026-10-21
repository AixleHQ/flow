# frozen_string_literal: true

require "test_helper"

class CompanySessionConcurrencyLimitTest < ActiveSupport::TestCase
  test "a preloaded limit is read without a query" do
    company = create(:company)
    SessionConcurrencyLimit.set!(scope: company, max_sessions: 7)

    loaded = Company.includes(:session_concurrency_limit_row).find(company.id)

    assert_no_queries { assert_equal 7, loaded.session_concurrency_limit }
  end

  test "a preloaded company without a limit is unbounded without a query" do
    company = create(:company)

    loaded = Company.includes(:session_concurrency_limit_row).find(company.id)

    assert_no_queries { assert_nil loaded.session_concurrency_limit }
  end

  test "without a preload the limit is read from the stored row" do
    company = create(:company)
    SessionConcurrencyLimit.set!(scope: company, max_sessions: 3)
    company = Company.find(company.id)

    assert_queries_match(/FROM "session_concurrency_limits"/, count: 1) do
      assert_equal 3, company.session_concurrency_limit
    end
  end

  # The row is preloaded before the form is assigned, so the assigned value must win.
  test "an assigned limit wins over the preloaded row" do
    company = create(:company)
    SessionConcurrencyLimit.set!(scope: company, max_sessions: 3)
    loaded = Company.includes(:session_concurrency_limit_row).find(company.id)

    loaded.session_concurrency_limit = "5"

    assert_equal "5", loaded.session_concurrency_limit
  end
end
