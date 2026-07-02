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
end
