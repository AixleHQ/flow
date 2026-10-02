# frozen_string_literal: true

require "test_helper"

class ChatTest < ActiveSupport::TestCase
  def event(event_type:, source:, data: {})
    TriggerEvent.new(event_type: event_type, source: source, data: data)
  end

  test "a chat message counts as Slack's only when Slack's own receiver produced it" do
    assert_equal Chat::SlackProvider,
                 Chat.provider_for(event(event_type: "chat.message", source: "slack:slack-team-T1",
                                         data: { "provider" => "slack" }))
    assert_nil Chat.provider_for(event(event_type: "chat.message", source: "generic:wh-1",
                                       data: { "provider" => "slack" }))
    assert_nil Chat.provider_for(event(event_type: "webhook.received", source: "slack:slack-team-T1"))
  end

  test "an event recorded before the messaging port is still Slack's" do
    assert_equal Chat::SlackProvider, Chat.provider_for(event(event_type: "slack.message", source: "slack:slack-team-T1"))
  end

  test "a Slack message matches chat triggers and the Slack triggers saved before them" do
    assert_equal %w[chat.message slack.message], Chat.event_types_for(Chat::SlackProvider)
  end

  test "a run's origin reads the chat block, or Slack's block for a run started before it existed" do
    chat = { "provider" => "slack", "conversation" => { "id" => "C1" }, "text" => "hi" }
    assert_equal chat, Chat.origin(WorkflowRun.new(shared_context: { "chat" => chat }))

    legacy = Chat.origin(WorkflowRun.new(shared_context: {
      "slack" => { "channel" => "C1", "ts" => "1.2", "thread_ts" => "1.1", "team" => "T1", "integration_id" => 7,
                   "text" => "deploy", "user" => "U1" }
    }))
    assert_equal "slack", legacy["provider"]
    assert_equal "C1", legacy.dig("conversation", "id")
    assert_equal "1.1", legacy["thread_id"]
    assert_equal "1.2", legacy["message_id"]
    assert_equal "U1", legacy.dig("actor", "id")
    assert_equal "deploy", legacy["text"]
    assert_equal 7, legacy["integration_id"]

    assert_nil Chat.origin(WorkflowRun.new(shared_context: {}))
  end
end
