# frozen_string_literal: true

require "test_helper"

class Feedback::NewCompanyAnnouncementTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  TOKEN = "xoxb-feedback-bot"
  CHANNEL = "C0FEEDBACK"

  setup do
    freeze_time
    @slack = stub_slack_client!
    @company = create(:company, name: "Acme <!channel> & Co", email_domain: "acme-robotics.example")
    @owner = create(:user, name: "Jane Doe", email: "jane@acme-robotics.example")
  end

  def configure(channel: CHANNEL)
    Settings.stubs(:feedback).returns(Hashie::Mash.new(slack_bot_token: TOKEN, slack_channel_id: channel))
  end

  def announce(**options)
    Feedback::NewCompanyAnnouncement.later(@company, **{ source: "signup", by: @owner }.merge(options))
    perform_enqueued_jobs
  end

  test "posts the company, who created it, when and how, with Slack's control characters escaped" do
    configure

    announce

    message = @slack.posted_messages.sole
    assert_equal [ TOKEN, CHANNEL ], message.values_at(:token, :channel)
    assert_equal <<~TEXT.chomp, message[:text]
      *🆕 New tenant: Acme &lt;!channel&gt; &amp; Co*
      *Source:* Self-serve signup (/workspace/new)
      *Tenant ID:* #{@company.id}
      *Domain:* acme-robotics.example
      *Created by:* Jane Doe (jane@acme-robotics.example)
      *Created:* #{Time.current.utc.strftime('%Y-%m-%d %H:%M UTC')}
    TEXT
  end

  test "a company from the admin names the operator and the first admin they invited" do
    configure
    operator = create(:user, :super_admin, name: "Olga Ops", email: "olga@ops.example")

    announce(source: "admin", by: operator, invited: "bob@acme-robotics.example")

    text = @slack.posted_messages.sole[:text]
    assert_includes text, "*Source:* Admin\n"
    assert_includes text, "*Created by:* Olga Ops (olga@ops.example)"
    assert_includes text, "*First admin invited:* bob@acme-robotics.example"
  end

  test "a Marketplace buyer's company says so" do
    configure

    announce(source: "marketplace")

    assert_includes @slack.posted_messages.sole[:text], "*Source:* AWS Marketplace signup"
  end

  test "posts nothing where the feedback channel is not configured" do
    configure(channel: "")

    announce

    assert_empty @slack.posted_messages
    assert_no_enqueued_jobs
  end

  test "a failure to queue the post is reported, never raised to the path that made the company" do
    configure
    Feedback::SlackPostJob.stubs(:perform_later).raises(ActiveRecord::ConnectionNotEstablished)

    assert_error_reported(ActiveRecord::ConnectionNotEstablished) do
      Feedback::NewCompanyAnnouncement.later(@company, source: "signup", by: @owner)
    end
  end
end
