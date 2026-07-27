# frozen_string_literal: true

require "test_helper"

class MembershipMailerTest < ActionMailer::TestCase
  setup do
    @company = create(:company, name: "Globex")
    @inviter = create(:user, :admin, company: @company)
    @invitee = create(:user, email: "invitee@example.com")
    @membership = create(:company_membership, :invited, :viewer,
                         user: @invitee, company: @company, invited_by: @inviter)
  end

  test "invitation email has the right recipient, subject and a working token link" do
    email = MembershipMailer.invitation(@membership)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ "invitee@example.com" ], email.to
    assert_includes email.subject, "Globex"

    body = email.text_part.decoded
    token = body[%r{/invitations/([^\s"]+)}, 1]
    assert token.present?, "invitation link with token expected in the email body"
    assert_equal @membership, CompanyMembership.find_by_token_for(:invitation, CGI.unescape(token))
  end

  test "invitation_reminder carries a still-valid token link and the expiry date" do
    @membership.update!(invited_at: 6.days.ago)
    email = MembershipMailer.invitation_reminder(@membership)

    assert_equal [ "invitee@example.com" ], email.to
    assert_includes email.subject, "expires soon"

    token = email.text_part.decoded[%r{/invitations/([^\s"]+)}, 1]
    assert_equal @membership, CompanyMembership.find_by_token_for(:invitation, CGI.unescape(token))
  end

  test "invitation_accepted goes to the inviter, not the member" do
    email = MembershipMailer.invitation_accepted(@membership)

    assert_equal [ @inviter.email ], email.to
    assert_includes email.subject, @invitee.name
  end

  test "access_revoked goes to the member and names the company" do
    email = MembershipMailer.access_revoked(@membership)

    assert_equal [ "invitee@example.com" ], email.to
    assert_includes email.subject, "Globex"
  end

  test "role_changed names both the old and the new role" do
    @membership.update!(role: "admin")
    email = MembershipMailer.role_changed(@membership, "employee")

    assert_equal [ "invitee@example.com" ], email.to
    body = email.text_part.decoded
    assert_includes body, "Employee"
    assert_includes body, "Admin"
  end
end
