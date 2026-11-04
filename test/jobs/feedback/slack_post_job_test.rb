# frozen_string_literal: true

require "test_helper"

class Feedback::SlackPostJobTest < ActiveJob::TestCase
  setup do
    Settings.stubs(:feedback).returns(Hashie::Mash.new(slack_bot_token: "xoxb-feedback-bot", slack_channel_id: "C0FEEDBACK"))
    @slack = stub_slack_client!
  end

  test "posts the text to the feedback channel" do
    Feedback::SlackPostJob.perform_now("*New tenant: Acme*")

    assert_equal [ "C0FEEDBACK", "*New tenant: Acme*" ], @slack.posted_messages.sole.values_at(:channel, :text)
  end

  test "an outage is tried again later" do
    @slack.send_error = Slack::Client::Error.new("internal_error")

    assert_enqueued_with(job: Feedback::SlackPostJob, args: [ "news" ]) do
      Feedback::SlackPostJob.perform_now("news")
    end
  end

  test "a bot that cannot post there fails the job instead of trying again" do
    @slack.send_error = Slack::Client::Error.new("not_in_channel")

    assert_raises(Feedback::DeliveryRejected) { Feedback::SlackPostJob.perform_now("news") }
    assert_no_enqueued_jobs
  end
end
