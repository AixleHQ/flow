# frozen_string_literal: true

require "test_helper"

module Webhooks
  class TriggerSupportTest < ActiveSupport::TestCase
    test "only an event the generic gateway took in carries its body into the run" do
      body = { "provider" => "slack", "title" => "Scan" }

      %w[generic:wh-1 github:wh-2 gitlab:wh-3].each do |source|
        event = TriggerEvent.new(source: source, data: body)
        assert_equal({ "webhook" => { "payload" => body } }, TriggerSupport.run_context(event), source)
      end
      %w[slack:ep teams:ep tracker chat_action manual].each do |source|
        assert_equal({}, TriggerSupport.run_context(TriggerEvent.new(source: source, data: body)), source)
      end
    end
  end
end
