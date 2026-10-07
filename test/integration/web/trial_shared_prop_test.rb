# frozen_string_literal: true

require "test_helper"

# The banner is fed by a shared Inertia prop, so every screen can say a workspace
# is on free capacity rather than leaving a person to work out why nothing
# starts.
class Web::TrialSharedPropTest < ActionDispatch::IntegrationTest
  setup do
    with_mode(Deployment::SAAS)
    @user = create(:user, :with_company, :onboarding_completed, password: AuthHelper::TEST_PASSWORD)
    @company = @user.companies.first
    sign_in_as(@user)
  end

  def with_mode(mode)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  def used!(hours)
    CompanyCapacityUsage.record!(
      company_id: @company.id, period_start: Time.utc(2026, 9, 29, 10), quantity_seconds: hours * 3600
    )
  end

  def trial_prop
    get company_projects_path
    captured = {}
    # The block's own return value is what the helper asserts on, and a workspace
    # with no allowance shares nothing — so capture and answer separately.
    assert_inertia_props do |shared|
      captured[:trial] = shared[:trial]
      true
    end
    captured[:trial]
  end

  test "a workspace somebody is paying for gets nothing" do
    assert_nil trial_prop
  end

  test "a workspace on free capacity gets what it has spent" do
    @company.update!(billing_state: "trialing")
    Settings.stubs(:trial).returns(Hashie::Mash.new(queue_hours: 100))
    with_company_limit(@company, 10)
    used!(60)

    props = trial_prop

    assert_equal "trialing", props[:state]
    assert_equal 100, props[:allowanceHours]
    assert_in_delta 60.0, props[:usedHours]
    assert_in_delta 40.0, props[:remainingHours]
    assert_equal 10, props[:maxSessions]
  end

  # Forty queue-hours is four days at one session and four hours at ten, and only
  # the second number answers when they have to do something about it.
  test "it turns what is left into hours at the rate they are running" do
    @company.update!(billing_state: "trialing")
    Settings.stubs(:trial).returns(Hashie::Mash.new(queue_hours: 100))
    with_company_limit(@company, 10)
    used!(60)

    assert_in_delta 4.0, trial_prop[:hoursLeftAtCurrentRate]
  end

  test "a workspace with no limit has no rate to divide by" do
    @company.update!(billing_state: "trialing")

    assert_nil trial_prop[:hoursLeftAtCurrentRate]
  end

  # The banner must not offer a card where there is nowhere to pay.
  test "it says whether there is a payment provider at all" do
    @company.update!(billing_state: "trialing")
    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: nil, price_id: nil))

    assert_not trial_prop[:canPay]
  end

  test "and says so when there is" do
    @company.update!(billing_state: "trialing")
    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: "sk_test", price_id: "price_test"))

    assert trial_prop[:canPay]
  end

  test "a workspace that has spent it says so" do
    @company.update!(billing_state: "blocked", billing_block_reason: "allowance")

    assert_equal "blocked", trial_prop[:state]
    assert_equal "allowance", trial_prop[:status]
  end

  # The banner offers what undoes the stop: a card for a spent allowance or an
  # ended subscription, the open invoice for a failed payment.
  test "a stopped workspace says why it was stopped" do
    @company.update!(billing_state: "blocked", billing_block_reason: "payment_failed")
    assert_equal "payment_failed", trial_prop[:status]

    @company.update!(billing_block_reason: "canceled")
    assert_equal "canceled", trial_prop[:status]
  end

  # Nobody is on an allowance outside the hosted product, whatever the column
  # happens to say.
  test "nothing is shared outside the hosted product" do
    @company.update!(billing_state: "trialing")
    with_mode(Deployment::SELF_HOSTED)

    assert_nil trial_prop
  end
end
