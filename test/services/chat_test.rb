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

  test "a chat message that names no messenger is nobody's" do
    assert_nil Chat.provider_for(event(event_type: "chat.message", source: "slack:slack-team-T1"))
  end

  test "a run's origin is its chat block" do
    chat = { "provider" => "slack", "conversation" => { "id" => "C1" }, "text" => "hi" }
    assert_equal chat, Chat.origin(WorkflowRun.new(shared_context: { "chat" => chat }))

    assert_nil Chat.origin(WorkflowRun.new(shared_context: {}))
  end
end
