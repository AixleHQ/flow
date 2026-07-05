# frozen_string_literal: true

require "test_helper"

module Slack
  class NotifierTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.company)
      @integration = Integration.create!(
        provider: :slack, company: @user.company, project: @project, connected_by: @user,
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

    test "post swallows Slack API errors and returns false" do
      fake_slack.stubs(:post_message).raises(Slack::Client::Error.new("channel_not_found"))

      assert_not Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi")
    end
  end
end
