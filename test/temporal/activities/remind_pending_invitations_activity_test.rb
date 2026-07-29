# frozen_string_literal: true

require "test_helper"

class Activities::Membership::RemindPendingInvitationsActivityTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    @company = create(:company)
    @inviter = create(:user, :admin, company: @company)

    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
  end

  def invitation(invited_at:, state: :invited, **attrs)
    create(:company_membership, state, user: create(:user), company: @company,
                                       invited_by: @inviter, invited_at: invited_at, **attrs)
  end

  def run_activity
    Activities::Membership::RemindPendingInvitationsActivity.new.run
  end

  test "reminds an invitation inside the final two days of its 7-day window" do
    membership = invitation(invited_at: 6.days.ago)

    assert_emails 1 do
      assert_equal({ reminded_count: 1 }, run_activity)
    end
    assert_equal [ membership.user.email ], ActionMailer::Base.deliveries.last.to

    assert membership.reload.reminded_at.present?
  end

  test "leaves a freshly sent invitation alone" do
    invitation(invited_at: 1.hour.ago)

    assert_no_emails do
      assert_equal({ reminded_count: 0 }, run_activity)
    end
  end

  test "skips invitations that already expired — their token is dead, so the link would go nowhere" do
    invitation(invited_at: 8.days.ago)

    assert_no_emails do
      assert_equal({ reminded_count: 0 }, run_activity)
    end
  end

  test "skips already-accepted and revoked memberships" do
    invitation(invited_at: 6.days.ago, state: :revoked)
    create(:company_membership, user: create(:user), company: @company,
                                invited_by: @inviter, invited_at: 6.days.ago)

    assert_no_emails do
      assert_equal({ reminded_count: 0 }, run_activity)
    end
  end

  # The cron runs hourly, so re-running must not re-mail: that is what
  # reminded_at is for.
  test "is idempotent across runs" do
    invitation(invited_at: 6.days.ago)

    assert_equal({ reminded_count: 1 }, run_activity)
    assert_no_emails do
      assert_equal({ reminded_count: 0 }, run_activity)
    end
  end

  test "a re-send clears the stamp so the new window gets its own reminder" do
    membership = invitation(invited_at: 6.days.ago)
    run_activity
    assert membership.reload.reminded_at.present?

    # Re-sending rotates invited_at, which starts a fresh 7-day window.
    membership.update!(invited_at: Time.current)
    assert_nil membership.reload.reminded_at

    membership.update!(invited_at: 6.days.ago)
    assert_equal({ reminded_count: 1 }, run_activity)
  end
end
