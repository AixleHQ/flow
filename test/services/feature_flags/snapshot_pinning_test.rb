# frozen_string_literal: true

require "test_helper"
require "temporalio/testing"

# Where a check pins its snapshot: in Current inside an executor run (a request,
# a job), nowhere outside one, which is where Temporal runs activities.
class FeatureFlags::SnapshotPinningTest < ActiveSupport::TestCase
  uses_feature_registry FeatureFlagsHelper::EXAMPLE_REGISTRY

  # Reports what a flag check inside an activity saw of the Rails executor.
  class CheckFlagActivity < Temporalio::Activity::Definition
    activity_name "feature_flags_pinning_probe"

    def execute
      Current.feature_snapshot = nil
      enabled = Feature.enabled?(:coder_reap)
      { "executor_active" => Rails.application.executor.active? == true, "pinned" => !Current.feature_snapshot.nil?,
        "enabled" => enabled }
    end
  end

  test "inside an executor run the first check pins the snapshot until Current resets" do
    Rails.application.executor.wrap do
      assert Feature.enabled?(:coder_reap)
      FeatureFlags.store.set_global(:coder_reap, false)

      assert Feature.enabled?(:coder_reap)
      assert_not_same FeatureFlags.store.snapshot, Current.feature_snapshot

      Current.reset
      refute Feature.enabled?(:coder_reap)
    end
  end

  test "outside an executor run every check reads the store and pins nothing" do
    seen = Thread.new do
      first = Feature.enabled?(:coder_reap)
      FeatureFlags.store.set_global(:coder_reap, false)
      [ Rails.application.executor.active? == true, first, Feature.enabled?(:coder_reap), Current.feature_snapshot ]
    end.value

    assert_equal [ false, true, false, nil ], seen
  end

  # The open question of the design (§5.2, §11): the SDK's default activity
  # executor runs activities on its own thread pool, outside any executor run,
  # and Activities::Base adds none. So nothing would clear a pin between two
  # activities on the same pool thread, and activities must not pin.
  test "a Temporal activity runs outside the Rails executor and does not pin" do
    result = Temporalio::Testing::ActivityEnvironment.new.run(CheckFlagActivity.new)

    assert_equal({ "executor_active" => false, "pinned" => false, "enabled" => true }, result)
  end
end
