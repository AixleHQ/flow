# frozen_string_literal: true

require "test_helper"

class TriggerDispatchTest < ActiveSupport::TestCase
  test "dedup_key is required" do
    dispatch = TriggerDispatch.new(trigger_event: create(:trigger_event), dedup_key: nil)
    assert_not dispatch.valid?
  end

  test "the DB unique index rejects a duplicate dedup_key" do
    event = create(:trigger_event)
    TriggerDispatch.create!(trigger_event: event, dedup_key: "dup-key", status: "matched")

    assert_raises(ActiveRecord::RecordNotUnique) do
      TriggerDispatch.create!(trigger_event: event, dedup_key: "dup-key", status: "matched")
    end
  end
end
