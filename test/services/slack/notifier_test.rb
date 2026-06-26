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
    end

    test "post sends via the client with the install's bot token and returns true" do
      Slack::Client.expects(:post_message)
        .with(has_entries(token: "xoxb-1", channel: "C1", text: "hi"))
        .once.returns({ "ok" => true })

      assert Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi")
    end

    test "post with files uploads them in one message via the client" do
      Slack::Client.expects(:upload_files)
        .with(has_entries(token: "xoxb-1", channel: "C1", initial_comment: "hi",
                          files: [ { filename: "a.rb", content: "x" } ]))
        .once.returns({ "ok" => true })
      Slack::Client.expects(:post_message).never

      assert Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi",
        files: [ { filename: "a.rb", content: "x" } ])
    end

    test "post is a no-op when neither text nor files are given" do
      Slack::Client.expects(:post_message).never
      Slack::Client.expects(:upload_files).never
      assert_not Slack::Notifier.post(integration: @integration, channel: "C1")
    end

    test "post is a no-op (false) when the integration is nil or channel blank" do
      Slack::Client.expects(:post_message).never
      assert_not Slack::Notifier.post(integration: nil, channel: "C1", text: "hi")
      assert_not Slack::Notifier.post(integration: @integration, channel: "", text: "hi")
    end

    test "post returns false when the install has no bot token" do
      @integration.update!(credentials_data: {})
      Slack::Client.expects(:post_message).never
      assert_not Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi")
    end

    test "post swallows Slack API errors and returns false" do
      Slack::Client.expects(:post_message).raises(Slack::Client::Error.new("channel_not_found"))
      assert_not Slack::Notifier.post(integration: @integration, channel: "C1", text: "hi")
    end

    test "notify_run replies into the originating Slack thread" do
      run = create(:workflow_run, project: @project, user: @user,
        shared_context: { "slack" => { "channel" => "C9", "thread_ts" => "5.5", "integration_id" => @integration.id } })

      Slack::Client.expects(:post_message)
        .with(has_entries(token: "xoxb-1", channel: "C9", thread_ts: "5.5"))
        .once.returns({ "ok" => true })

      assert Slack::Notifier.notify_run(run, "done")
    end

    test "notify_run is a no-op for non-Slack runs" do
      run = create(:workflow_run, project: @project, user: @user, shared_context: {})
      Slack::Client.expects(:post_message).never
      assert_not Slack::Notifier.notify_run(run, "done")
    end
  end
end
