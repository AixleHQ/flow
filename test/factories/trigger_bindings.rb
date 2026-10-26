# frozen_string_literal: true

FactoryBot.define do
  factory :trigger_binding do
    transient do
      # A chat trigger names its messenger; nil leaves it unnamed.
      chat_provider { "slack" }
      # A chat trigger listens in one channel connected to its company: this
      # channel id (a `channel` condition in filter_predicate wins), or none when nil.
      chat_channel { :default }
    end

    project { nil }   # pass explicitly: create(:trigger_binding, project:, workflow:, created_by:)
    workflow { nil }
    created_by factory: :user

    sequence(:name) { |n| "binding-#{n}" }
    event_type { "chat.message" }
    filter_predicate { {} }
    trigger_mode { :auto }
    enabled { true }
    cooldown_seconds { 0 }

    after(:build) do |binding, evaluator|
      next unless binding.event_type == "chat.message"

      filter = binding.filter_predicate.to_h
      filter = { "provider" => evaluator.chat_provider }.merge(filter) if evaluator.chat_provider && !filter.key?("provider")
      channel = filter["channel"].is_a?(String) ? filter.delete("channel") : evaluator.chat_channel
      if binding.chat_conversation.nil? && channel && filter["provider"] && binding.project
        binding.chat_conversation = ChatChannelTestHelper.connect_chat_channel(
          company: binding.project.company, provider: filter["provider"],
          external_id: channel == :default ? nil : channel
        )
      end
      binding.filter_predicate = filter
    end
  end
end
