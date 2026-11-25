# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261125100001_backfill_product_tour_finished")

class BackfillProductTourFinishedTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  def migrate
    BackfillProductTourFinished.new.tap { |m| m.suppress_messages { m.up } }
  end

  test "a member who finished onboarding has finished both tours, one still onboarding has not" do
    onboarded_at = 3.days.ago.change(usec: 0)
    onboarded = create(:company_membership, user: create(:user), company: @company,
                                            onboarding_state: "completed", onboarding_completed_at: onboarded_at)
    onboarding = create(:company_membership, user: create(:user), company: @company, onboarding_state: "step2")

    migrate

    assert_equal [ onboarded_at, onboarded_at ],
                 [ onboarded.reload.product_tour_a_finished_at, onboarded.product_tour_b_finished_at ]
    assert_nil onboarding.reload.product_tour_a_finished_at
    assert_nil onboarding.product_tour_b_finished_at
    assert_not onboarded.getting_started_pending?
  end

  test "a tour already finished keeps its time" do
    finished_at = 1.hour.ago.change(usec: 0)
    membership = create(:company_membership, user: create(:user), company: @company,
                                             onboarding_state: "completed", onboarding_completed_at: 3.days.ago,
                                             product_tour_a_finished_at: finished_at)

    migrate

    assert_equal finished_at, membership.reload.product_tour_a_finished_at
  end
end
