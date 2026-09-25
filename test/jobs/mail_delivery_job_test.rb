# frozen_string_literal: true

require "test_helper"

class MailDeliveryJobTest < ActiveJob::TestCase
  # A delivery method that fails the way an SMTP server does.
  class RefusingDelivery
    cattr_accessor :error

    def initialize(_settings); end

    def deliver!(_mail)
      raise error
    end
  end

  ActionMailer::Base.add_delivery_method :refusing_for_test, RefusingDelivery

  setup do
    company = create(:company)
    @membership = create(:company_membership, :invited, user: create(:user), company: company,
                                                        invited_by: create(:user, :admin, company: company))
    @delivery_method = ActionMailer::Base.delivery_method
    @raise_delivery_errors = ActionMailer::Base.raise_delivery_errors
    ActionMailer::Base.delivery_method = :refusing_for_test
    ActionMailer::Base.raise_delivery_errors = true
  end

  teardown do
    ActionMailer::Base.delivery_method = @delivery_method
    ActionMailer::Base.raise_delivery_errors = @raise_delivery_errors
  end

  def deliver_invitation
    MailDeliveryJob.perform_now("MembershipMailer", "invitation", "deliver_now", args: [ @membership ])
  end

  test "every mailer delivers through the retrying job" do
    assert_enqueued_with(job: MailDeliveryJob) { MembershipMailer.invitation(@membership).deliver_later }
  end

  test "a busy SMTP server gets the invitation again later" do
    RefusingDelivery.error = Net::SMTPServerBusy.new("451 4.7.1 try again later")

    assert_enqueued_with(job: MailDeliveryJob) { deliver_invitation }
  end

  test "a connection that times out gets the invitation again later" do
    RefusingDelivery.error = Net::OpenTimeout.new("execution expired")

    assert_enqueued_with(job: MailDeliveryJob) { deliver_invitation }
  end

  test "a refused recipient fails the job instead of retrying" do
    RefusingDelivery.error = Net::SMTPFatalError.new("550 5.1.1 no such user")

    assert_no_enqueued_jobs do
      assert_raises(Net::SMTPFatalError) { deliver_invitation }
    end
  end
end
