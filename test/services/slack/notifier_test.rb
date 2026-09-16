# frozen_string_literal: true

require "test_helper"

module Slack
  class NotifierTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.companies.first)
      @integration = Integration.create!(
        provider: :slack, company: @user.companies.first, project: @project, connected_by: @user,
        name: "Acme", status: :active
      )
      @integration.update!(credentials_data: { "bot_token" => "xoxb-1" })
      stub_slack_client!
    end

    test "post sends via the client with the install's bot token and returns true" do
      assert Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi")

      assert_equal 1, fake_slack.posted_messages.size
      msg = fake_slack.last_posted_message
      assert_equal "xoxb-1", msg[:token]
      assert_equal "C1", msg[:channel]
      assert_equal "hi", msg[:text]
    end

    test "post with files uploads them in one message via the client" do
      assert Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi",
        files: [ { filename: "a.rb", content: "x" } ])

      assert_equal 1, fake_slack.uploaded_files.size
      upload = fake_slack.last_uploaded_files
      assert_equal "xoxb-1", upload[:token]
      assert_equal "C1", upload[:channel]
      assert_equal "hi", upload[:initial_comment]
      assert_equal 1, upload[:files].size
      assert_equal "a.rb", upload[:files].first[:filename]
      assert_equal "x", upload[:files].first[:content]
      assert_empty fake_slack.posted_messages
    end

    test "post is a no-op when neither text nor files are given" do
      assert_not Slack::Notifier.post(integration: @integration, channel: "C1")

      assert_empty fake_slack.posted_messages
      assert_empty fake_slack.uploaded_files
    end

    test "post is a no-op (false) when the integration is nil or channel blank" do
      assert_not Slack::Notifier.post(integration: nil, channel: "C1", text: "hi")
      assert_not Slack::Notifier.post(integration: @integration, channel: "", text: "hi")

      assert_empty fake_slack.posted_messages
    end

    test "post returns false when the install has no bot token" do
      @integration.update!(credentials_data: {})

      assert_not Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi")

      assert_empty fake_slack.posted_messages
    end

    test "post swallows Slack API errors and returns nothing" do
      fake_slack.stubs(:post_message).raises(Slack::Client::Error.new("channel_not_found"))

      assert_not Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi")
    end

    test "post returns the posted message's coordinates" do
      result = Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi", thread_ts: "5.5")

      assert result.ok?
      assert_equal "C1", result.channel
      assert_equal "5.5", result.thread_ts
      assert_equal fake_slack.last_posted_message_ts, result.ts
      assert_empty result.errors
    end

    test "post sends blocks and reply_broadcast through to the client" do
      blocks = [ { "type" => "divider" } ]

      assert Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi",
        blocks: blocks, thread_ts: "5.5", reply_broadcast: true)

      msg = fake_slack.last_posted_message
      assert_equal blocks, msg[:blocks]
      assert msg[:reply_broadcast]
    end

    test "post with blocks AND files sends the message, then the files into its thread" do
      result = Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi",
        blocks: [ { "type" => "divider" } ], files: [ { filename: "a.rb", content: "x" } ])

      assert result.ok?
      assert_equal 1, fake_slack.posted_messages.size
      assert_equal 1, fake_slack.uploaded_files.size
      assert_equal result.ts, fake_slack.last_uploaded_files[:thread_ts]
      assert_nil fake_slack.last_uploaded_files[:initial_comment]
    end

    test "post with blocks and files keeps an explicit thread for both" do
      Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi", thread_ts: "5.5",
        blocks: [ { "type" => "divider" } ], files: [ { filename: "a.rb", content: "x" } ])

      assert_equal "5.5", fake_slack.last_posted_message[:thread_ts]
      assert_equal "5.5", fake_slack.last_uploaded_files[:thread_ts]
    end

    test "post reports a half-delivered send instead of swallowing it" do
      fake_slack.stubs(:upload_files).raises(Slack::Client::Error.new("upload_failed"))

      result = Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi",
        blocks: [ { "type" => "divider" } ], files: [ { filename: "a.rb", content: "x" } ])

      assert_not result.ok?
      assert result.ts.present?
      assert_match(/files: upload_failed/, result.error_message)
    end

    test "post falls back to carrying the text on the upload when the message fails" do
      fake_slack.stubs(:post_message).raises(Slack::Client::Error.new("invalid_blocks"))

      result = Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi",
        blocks: [ { "type" => "divider" } ], files: [ { filename: "a.rb", content: "x" } ])

      assert_not result.ok?
      assert_nil result.ts
      assert_equal "hi", fake_slack.last_uploaded_files[:initial_comment]
    end

    test "post returns nothing when every request fails" do
      fake_slack.stubs(:post_message).raises(Slack::Client::Error.new("invalid_blocks"))
      fake_slack.stubs(:upload_files).raises(Slack::Client::Error.new("upload_failed"))

      assert_not Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi",
        blocks: [ { "type" => "divider" } ], files: [ { filename: "a.rb", content: "x" } ])
    end

    test "post sends blocks with no text at all" do
      assert Slack::Notifier.post(integration: @integration, channel: "C1",
        blocks: [ { "type" => "divider" } ])

      assert_equal 1, fake_slack.posted_messages.size
    end
  end
end
