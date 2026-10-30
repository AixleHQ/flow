# frozen_string_literal: true

require "test_helper"

class Feedback::SlackDestinationTest < ActiveSupport::TestCase
  include SlackTestHelper

  TOKEN = "xoxb-feedback-bot"
  CHANNEL = "C0FEEDBACK"

  setup do
    freeze_time
    Settings.stubs(:feedback).returns(Hashie::Mash.new(slack_bot_token: TOKEN, slack_channel_id: CHANNEL))
    @slack = stub_slack_client!
    company = create(:company, name: "Acme")
    @user = create(:user, company: company, name: "Jane Doe")
    @submission = create(:feedback_submission, company: company, user: @user, kind: "feature_request",
                                               message: "Export the board <!channel>\nas CSV & PDF",
                                               page_url: "https://flow.example.com/company/projects/7/board",
                                               app_version: "1.8.0")
  end

  def deliver = Feedback::SlackDestination.new(@submission).deliver

  def attach(name, content)
    @submission.attach([ Rack::Test::UploadedFile.new(StringIO.new(content), "application/octet-stream", original_filename: name) ])
  end

  test "posts the message, who sent it and from where, with Slack's control characters escaped" do
    deliver

    message = @slack.posted_messages.sole
    assert_equal [ TOKEN, CHANNEL ], message.values_at(:token, :channel)
    assert_equal <<~TEXT.chomp, message[:text]
      *Feature request: Export the board &lt;!channel&gt;*
      > Export the board &lt;!channel&gt;
      > as CSV &amp; PDF
      *Type:* Feature request
      *From:* Jane Doe (#{@user.email})
      *Company:* Acme
      *Page:* https://flow.example.com/company/projects/7/board
      *Version:* 1.8.0
      *Sent:* #{Time.current.utc.strftime('%Y-%m-%d %H:%M UTC')}
    TEXT
    assert_empty @slack.uploaded_files
    assert_equal Time.current, @submission.reload.slack_delivered_at
  end

  test "sends the files with the message, as one post" do
    attach("board.png", "PNG bytes")
    attach("console.log", "TypeError: columns")
    @submission.save!

    deliver

    upload = @slack.uploaded_files.sole
    assert_equal [ TOKEN, CHANNEL ], upload.values_at(:token, :channel)
    assert_equal [ [ "board.png", "PNG bytes" ], [ "console.log", "TypeError: columns" ] ],
                 upload[:files].map { |file| file.values_at(:filename, :content) }
    assert_match(/\A\*Feature request: Export the board/, upload[:initial_comment])
    assert_empty @slack.posted_messages
  end

  test "posts once" do
    deliver
    deliver

    assert_equal 1, @slack.posted_messages.size
  end

  test "a rate limit or an outage is worth another attempt" do
    [ Slack::Client::RateLimited.new(30), Slack::Client::Error.new("internal_error"),
      Faraday::ConnectionFailed.new("connection refused") ].each do |error|
      @slack.send_error = error

      assert_raises(Feedback::DeliveryFailed) { deliver }
    end
    assert_nil @submission.reload.slack_delivered_at
  end

  test "a bot that cannot post there is refused for good, without its token in the error" do
    @slack.send_error = Slack::Client::Error.new("not_in_channel")

    error = assert_raises(Feedback::DeliveryRejected) { deliver }

    assert_match(/not_in_channel/, error.message)
    assert_no_match(/xoxb/, error.message)
    assert_nil @submission.reload.slack_delivered_at
  end
end
