# frozen_string_literal: true

require "test_helper"

class Web::Company::SessionsPolicyTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  def policy_for(user)
    Web::Company::SessionsPolicy.new(BaseContext.new(user, ActionController::Parameters.new), nil)
  end

  test "index?, new?, and show? are all true for an admin" do
    admin = create(:user, :admin, :onboarding_completed, company: @company)
    policy = policy_for(admin)
    assert policy.index?
    # new? has no company-level route/action; this unit test is the only thing
    # that exercises it, so keep the assertion.
    assert policy.new?
    assert policy.show?
  end

  test "index?, new?, and show? are all false for an employee" do
    employee = create(:user, :employee, :onboarding_completed, company: @company)
    policy = policy_for(employee)
    assert_not policy.index?
    assert_not policy.new?
    assert_not policy.show?
  end
end
