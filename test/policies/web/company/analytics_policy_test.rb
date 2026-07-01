# frozen_string_literal: true

require "test_helper"

class Web::Company::AnalyticsPolicyTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  def policy_for(user)
    Web::Company::AnalyticsPolicy.new(BaseContext.new(user, ActionController::Parameters.new), nil)
  end

  test "index? is true for an admin" do
    admin = create(:user, :admin, :onboarding_completed, company: @company)
    assert policy_for(admin).index?
  end

  test "index? is false for an employee" do
    employee = create(:user, :employee, :onboarding_completed, company: @company)
    assert_not policy_for(employee).index?
  end
end
