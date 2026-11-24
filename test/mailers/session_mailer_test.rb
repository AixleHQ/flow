# frozen_string_literal: true

require "test_helper"

class SessionMailerTest < ActionMailer::TestCase
  setup do
    @user = create(:user, :with_company, email: "owner@example.com")
    @project = create(:project, owner: @user, company: @user.companies.first)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project, state: "suspended",
                                                         suspended_at: Time.utc(2026, 11, 20), restore_expires_at: Time.utc(2026, 12, 20))
  end

  test "suspended tells the owner until when the session can be restored, and links to it" do
    mail = SessionMailer.suspended(@session.id)

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "Your session ##{@session.id} was suspended — restore it by December 20, 2026", mail.subject
    assert_includes mail.text_part.body.to_s, "23-hour limit"
    assert_includes mail.html_part.body.to_s, "/company/#{@project.company.slug}/projects/#{@project.id}/sessions/#{@session.id}"
  end

  test "the reminder is not sent for a session that was restored meanwhile" do
    put_session_in_state!(@session, "restored")

    assert_nil SessionMailer.restore_expiring(@session.id).message.to
  end

  test "the reminder names the last day" do
    mail = SessionMailer.restore_expiring(@session.id)

    assert_equal "Session ##{@session.id} can be restored until December 20, 2026", mail.subject
  end
end
