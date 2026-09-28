# frozen_string_literal: true

require "test_helper"

# The drain and the meter read one number (Billing::EffectiveCapacity). These are
# the drain's half: a company on the free allowance runs one session at a time
# however high it set its limit, and one that has spent the allowance runs none.
class SessionAdmissionBillingTest < ActiveSupport::TestCase
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    with_company_limit(@company, 10)
  end

  def enqueue
    SessionAdmissionService.enqueue!(create(:terminal_session, user: @user, project: @project))
  end

  test "a paying company runs what it asked for" do
    admissions = 3.times.map { enqueue }

    assert_equal admissions.map(&:id), SessionAdmissionService.drain!
  end

  test "a company on the free allowance runs one at a time" do
    @company.update!(billing_state: "trialing")
    first = enqueue
    second = enqueue

    assert_equal [ first.id ], SessionAdmissionService.drain!
    assert_nil second.reload.admitted_at
  end

  # Nothing kills what is already running — only nothing new starts.
  test "a company that has spent it runs nothing new" do
    @company.update!(billing_state: "blocked")
    enqueue

    assert_empty SessionAdmissionService.drain!
  end

  test "paying reopens the queue" do
    @company.update!(billing_state: "blocked")
    queued = enqueue
    assert_empty SessionAdmissionService.drain!

    @company.update!(billing_state: "active")

    assert_equal [ queued.id ], SessionAdmissionService.drain!
  end

  # Outside the hosted product nobody is on an allowance, whatever the column
  # happens to say.
  test "the state is ignored where nothing is billed" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))
    @company.update!(billing_state: "blocked")
    queued = enqueue

    assert_equal [ queued.id ], SessionAdmissionService.drain!
  end
end
