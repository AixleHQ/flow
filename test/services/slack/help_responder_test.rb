# frozen_string_literal: true

require "test_helper"

module Slack
  class HelpResponderTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company, name: "Acme App")
      @integration = Integration.create!(
        provider: :slack, company: @company, project: nil, connected_by: @user,
        name: "Acme", status: :active
      )
      @integration.update!(credentials_data: { "bot_token" => "xoxb-1" })
      stub_slack_client!

      @workflow = create(:workflow, scope: @project, name: "Ship Report")
      create(:step, workflow: @workflow, name: "Go", position: 1, allow_non_interactive: true)
    end

    def event(data: {}, company: @company, project: nil)
      TriggerEvent.create!(
        event_type: "slack.message",
        source: "slack:acme",
        company: company,
        project: project,
        data: {
          "channel" => "C1",
          "ts" => "111.222",
          "thread_ts" => "111.222",
          "integration_id" => @integration.id,
          "text" => "<@B> /help"
        }.merge(data),
        occurred_at: Time.current
      )
    end

    test "posts a Block Kit catalog of channel triggers into the thread" do
      create(:trigger_binding,
        project: @project, workflow: @workflow, created_by: @user, name: "ship",
        event_type: "slack.message",
        filter_predicate: { "channel" => "C1", "text" => { "op" => "contains", "value" => "ship" } })

      assert Slack::HelpResponder.call(event)

      msg = fake_slack.last_posted_message
      assert_equal "xoxb-1", msg[:token]
      assert_equal "C1", msg[:channel]
      assert_equal "111.222", msg[:thread_ts]
      assert_match(/Available commands/, msg[:text])
      assert_match(/ship/, msg[:text])
      assert_match(/Ship Report/, msg[:text])
      assert_match(/contains "ship"/, msg[:text])
      assert_match(/Acme App/, msg[:text])
      assert msg[:blocks].present?
      assert_equal "section", msg[:blocks].first["type"]
    end

    test "lists only bindings that apply to the event channel" do
      create(:trigger_binding,
        project: @project, workflow: @workflow, created_by: @user, name: "here",
        event_type: "slack.message",
        filter_predicate: { "channel" => "C1", "text" => { "op" => "contains", "value" => "here" } })
      create(:trigger_binding,
        project: @project, workflow: @workflow, created_by: @user, name: "elsewhere",
        event_type: "slack.message",
        filter_predicate: { "channel" => "C99", "text" => { "op" => "contains", "value" => "elsewhere" } })
      create(:trigger_binding,
        project: @project, workflow: @workflow, created_by: @user, name: "any-channel",
        event_type: "slack.message",
        filter_predicate: { "text" => { "op" => "contains", "value" => "any" } })

      assert Slack::HelpResponder.call(event)

      text = fake_slack.last_posted_message[:text]
      assert_match(/here/, text)
      assert_match(/\*any\*/, text)
      assert_no_match(/elsewhere/, text)
      assert_no_match(/any-channel/, text)
    end

    test "names a command by its text pattern and the workflow, not the binding name" do
      create(:trigger_binding,
        project: @project, workflow: @workflow, created_by: @user, name: "Custom Label",
        event_type: "slack.message",
        filter_predicate: { "channel" => "C1", "text" => { "op" => "contains", "value" => "deploy" } })

      assert Slack::HelpResponder.call(event)
      text = fake_slack.last_posted_message[:text]
      assert_match(/\*deploy\* — Ship Report/, text)
      assert_no_match(/Custom Label/, text)
    end

    test "uses the workflow name alone when the text pattern is blank" do
      create(:trigger_binding,
        project: @project, workflow: @workflow, created_by: @user, name: "Custom Label",
        event_type: "slack.message",
        filter_predicate: { "channel" => "C1" })

      assert Slack::HelpResponder.call(event)
      text = fake_slack.last_posted_message[:text]
      assert_match(/\*Ship Report\* \(any message\)/, text)
      assert_no_match(/Custom Label/, text)
      assert_no_match(/Ship Report — Ship Report/, text)
    end

    test "says so when no triggers apply to the channel" do
      create(:trigger_binding,
        project: @project, workflow: @workflow, created_by: @user, name: "other",
        event_type: "slack.message",
        filter_predicate: { "channel" => "C99" })

      assert Slack::HelpResponder.call(event)
      assert_match(/No Slack triggers configured/, fake_slack.last_posted_message[:text])
    end

    test "stays quiet without an integration" do
      @integration.update!(status: :inactive)

      assert_not Slack::HelpResponder.call(event)
      assert_empty fake_slack.posted_messages
    end

    test "stays quiet for a non-Slack event" do
      ev = TriggerEvent.create!(
        event_type: "webhook.received", source: "wh", company: @company,
        data: { "channel" => "C1" }, occurred_at: Time.current
      )

      assert_not Slack::HelpResponder.call(ev)
      assert_empty fake_slack.posted_messages
    end

    test "a Slack outage is swallowed, never raised at the caller" do
      Slack::Notifier.stubs(:post).raises(StandardError, "slack is down")

      assert_not Slack::HelpResponder.call(event)
    end
  end
end
