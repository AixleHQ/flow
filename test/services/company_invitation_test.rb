# frozen_string_literal: true

require "test_helper"

class CompanyInvitationTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @company = create(:company)
    @inviter = create(:user, :super_admin)
  end

  test "a new address becomes a passwordless user with a pending invitation, and is mailed" do
    result = nil
    assert_enqueued_emails 1 do
      result = invite(" Jane.Doe@Example.com ", role: "admin")
    end

    assert_equal :invited, result.status
    assert_equal "Invitation sent to jane.doe@example.com", result.message
    user = User.find_by!(email: "jane.doe@example.com")
    assert_equal "Jane Doe", user.name
    assert_empty user.user_identities
    membership = @company.company_memberships.find_by!(user: user)
    assert { membership.invited? && membership.admin? }
    assert_equal @inviter, membership.invited_by
  end

  test "a pending invitation is sent again with a fresh link" do
    member = create(:user, company: @company, membership_state: "invited")
    membership = @company.company_memberships.find_by!(user: member)
    membership.update!(invited_at: 2.days.ago)
    old_token = membership.generate_token_for(:invitation)

    result = nil
    assert_no_difference -> { CompanyMembership.count } do
      assert_enqueued_email_with MembershipMailer, :invitation, args: [ membership ] do
        result = invite(member.email)
      end
    end

    assert_equal :resent, result.status
    assert_nil CompanyMembership.find_by_token_for(:invitation, old_token)
  end

  test "a revoked member is invited again in the same row, with the role asked for" do
    member = create(:user, :employee, company: @company)
    membership = @company.company_memberships.find_by!(user: member)
    membership.revoke!

    result = invite(member.email, role: "viewer")

    assert_equal :invited, result.status
    membership.reload
    assert { membership.invited? && membership.viewer? }
    assert_equal @inviter, membership.invited_by
  end

  test "members and platform administrators are left alone" do
    member = create(:user, :employee, company: @company)
    super_admin = create(:user, :super_admin)

    assert_no_enqueued_emails do
      assert_equal :already_member, invite(member.email).status
      assert_equal :platform_admin, invite(super_admin.email).status
    end
    assert_empty super_admin.company_memberships
  end

  test "an address that is not one reports why" do
    result = nil
    assert_no_difference -> { User.count } do
      result = invite("not-an-email")
    end

    assert_equal :invalid, result.status
    assert_match(/not-an-email: Email is invalid/, result.message)
  end

  test "a pasted list is split on commas, semicolons and new lines, each address invited once" do
    results = CompanyInvitation.invite_all(
      company: @company, inviter: @inviter, role: "employee",
      addresses: "ann@example.com, bob@example.com;\nANN@example.com\n\n  carl@example.com"
    )

    assert_equal %w[ann@example.com bob@example.com carl@example.com], results.map(&:email)
    assert results.all?(&:sent?)
    assert_equal 3, @company.company_memberships.where(state: "invited").count
  end

  private

  def invite(email, role: nil)
    CompanyInvitation.call(company: @company, inviter: @inviter, email: email, role: role)
  end
end

class CompanyInvitationUnqueuedMailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test = FailingMailQueueAdapter.new

  test "an invitation whose email cannot be queued stays pending, to be sent again" do
    company = create(:company)

    result = CompanyInvitation.call(company: company, email: "ann@example.com", role: "admin")

    assert_equal :unsent, result.status
    assert { result.unsent? && !result.sent? }
    assert_equal "ann@example.com is invited, but the email could not be sent. Re-send the invitation", result.message
    membership = company.company_memberships.joins(:user).find_by!(users: { email: "ann@example.com" })
    assert { membership.invited? && membership.admin? }
  end
end
